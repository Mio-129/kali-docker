#!/usr/bin/env bash
#
# GitHub Codespaces acildiginda (postCreateCommand) Docker komutlariyla Kali Linux'u kurar:
#   0. docker yoksa -> Docker-in-Docker (CLI + dockerd) kendisi kurar / baslatir
#   1. docker pull  -> Kali taban imaji
#   2. docker build -> Dockerfile / cli hedefi (terminal imaji)
#   3. docker build -> Dockerfile / desktop hedefi (XFCE + noVNC masaustu imaji)
#   4. docker run   -> 6080 (noVNC) ve 5901 (VNC) portlarini yayinlayan Kali konteyneri
#   5. `kali`       -> konteynere giren kisa yol komutu
#
# Kullanim:
#   bash .devcontainer/setup-kali.sh               # ilk kurulum (postCreateCommand)
#   bash .devcontainer/setup-kali.sh --start-only  # yeniden baslatma (postStartCommand)
#
# Ortam degiskenleri:
#   KALI_AUTO_INSTALL_DOCKER       1 = docker eksikse kur (varsayilan: 1)
#   KALI_DESKTOP                   1 = noVNC masaustu acik, 0 = sadece terminal (varsayilan: 1)
#   KALI_IMAGE                     CLI imaji             (kali-docker:local)
#   KALI_DESKTOP_IMAGE             masaustu imaji        (kali-docker:desktop)
#   KALI_CONTAINER                 konteyner adi         (kali)
#   KALI_WORKSPACE                 baglanan dizin        (repo koku)
#   KALI_WEB_PORT                  noVNC host portu      (6080)
#   KALI_VNC_PORT                  VNC host portu        (5901)
#   KALI_VNC_PASSWORD              noVNC/VNC sifresi     (kali)
#   KALI_VNC_RESOLUTION            ekran cozunurlugu     (1280x800x24)
#   KALI_PORTAINER                 1 = Docker web paneli (varsayilan: 0)
#   KALI_PORTAINER_PORT            Portainer host portu  (9443)
#   KALI_DOCKER_WAIT_ATTEMPTS      daemon deneme sayisi  (45, her biri 2 saniye)
#   KALI_FALLBACK_WAIT_ATTEMPTS    kendi dockerd'imiz icin deneme sayisi (10)
#   KALI_DESKTOP_WAIT_ATTEMPTS     noVNC deneme sayisi   (30, her biri 1 saniye)

set -euo pipefail

START_ONLY=0
if [[ "${1:-}" == "--start-only" ]]; then
    START_ONLY=1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_IMAGE="kalilinux/kali-rolling"
IMAGE="${KALI_IMAGE:-kali-docker:local}"
DESKTOP_IMAGE="${KALI_DESKTOP_IMAGE:-kali-docker:desktop}"
DESKTOP="${KALI_DESKTOP:-1}"
CONTAINER="${KALI_CONTAINER:-kali}"
WORKSPACE="${KALI_WORKSPACE:-$ROOT_DIR}"
WEB_PORT="${KALI_WEB_PORT:-6080}"
VNC_PORT="${KALI_VNC_PORT:-5901}"
VNC_PASSWORD="${KALI_VNC_PASSWORD:-kali}"
RESOLUTION="${KALI_VNC_RESOLUTION:-1280x800x24}"
PORTAINER="${KALI_PORTAINER:-0}"
PORTAINER_PORT="${KALI_PORTAINER_PORT:-9443}"
PORTAINER_CONTAINER="${KALI_PORTAINER_CONTAINER:-portainer}"
AUTO_INSTALL_DOCKER="${KALI_AUTO_INSTALL_DOCKER:-1}"
WAIT_ATTEMPTS="${KALI_DOCKER_WAIT_ATTEMPTS:-45}"
FALLBACK_WAIT_ATTEMPTS="${KALI_FALLBACK_WAIT_ATTEMPTS:-10}"
DESKTOP_WAIT_ATTEMPTS="${KALI_DESKTOP_WAIT_ATTEMPTS:-30}"
DOCKER=(docker)
SUDO=()
DOCKER_FALLBACK=0

TARGET_IMAGE="${IMAGE}"
if [[ "${DESKTOP}" == "1" ]]; then
    TARGET_IMAGE="${DESKTOP_IMAGE}"
fi

# docker-in-docker feature'i build sirasinda bu dosyayi olusturur. Yoksa (ornegin
# recovery konteyneri) kendi dockerd'imizi baslatmamiz gerekir.
FEATURE_INSTALLED=0
if [[ -x /usr/local/share/docker-init.sh ]]; then
    FEATURE_INSTALLED=1
fi

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '(!) %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Docker-in-Docker kurulumu (feature yoksa / Docker CLI eksikse)
# ---------------------------------------------------------------------------
detect_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        SUDO=()
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        SUDO=(sudo -n)
        return 0
    fi
    return 1
}

install_docker_packages() {
    # Paket yoneticisine gore Docker CLI + daemon kur.
    if command -v apt-get >/dev/null 2>&1; then
        log "Docker-in-Docker kuruluyor: docker.io (apt)"
        if "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update -qq \
            && "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io; then
            return 0
        fi
        return 1
    fi
    if command -v apk >/dev/null 2>&1; then
        log "Docker-in-Docker kuruluyor: docker + docker-cli (apk / Alpine)"
        if "${SUDO[@]}" apk add --no-cache docker docker-cli; then
            return 0
        fi
        return 1
    fi
    if command -v dnf >/dev/null 2>&1; then
        log "Docker-in-Docker kuruluyor: docker (dnf)"
        if "${SUDO[@]}" dnf install -y docker; then
            return 0
        fi
        return 1
    fi
    if command -v yum >/dev/null 2>&1; then
        log "Docker-in-Docker kuruluyor: docker (yum)"
        if "${SUDO[@]}" yum install -y docker; then
            return 0
        fi
        return 1
    fi
    warn "Desteklenen paket yoneticisi bulunamadi (apt-get / apk / dnf / yum)."
    return 1
}

ensure_docker() {
    if command -v docker >/dev/null 2>&1; then
        return 0
    fi
    if ! detect_sudo; then
        warn "Docker CLI eksik ve root/sudo kullanilamiyor; paket kurulamadi."
        return 1
    fi
    if ! install_docker_packages; then
        warn "Docker paketleri kurulamadi (depo erisimi veya yetki sorunu olabilir)."
        return 1
    fi
    # Ayni shell oturumunda yeni kurulan komutlar icin bash lookup cache'ini temizle.
    hash -r 2>/dev/null || true
    if ! command -v docker >/dev/null 2>&1; then
        warn "Kurulumdan sonra hala docker CLI bulunamadi."
        return 1
    fi
    return 0
}

start_dockerd() {
    if ! command -v dockerd >/dev/null 2>&1; then
        warn "dockerd bulunamadi; Docker-in-Docker baslatilamadi."
        return 1
    fi
    # Ayricaliksiz (unprivileged) ortamlarda overlayfs/iptables kullanilamayabilir;
    # vfs + bridge/iptables kapali ile en iyi efforsla baslat.
    log "Docker-in-Docker daemon baslatiliyor (vfs, iptables/bridge kapali)"
    "${SUDO[@]}" dockerd \
        --host=unix:///var/run/docker.sock \
        --storage-driver=vfs \
        --iptables=false \
        --bridge=none \
        >/tmp/kali-dockerd.log 2>&1 &
    DOCKER_FALLBACK=1
    return 0
}

docker_ready() {
    if docker info >/dev/null 2>&1; then
        return 0
    fi
    if sudo -n true 2>/dev/null && sudo -n docker info >/dev/null 2>&1; then
        DOCKER=(sudo docker)
        return 0
    fi
    return 1
}

wait_for_docker() {
    local attempt
    for (( attempt = 1; attempt <= WAIT_ATTEMPTS; attempt++ )); do
        if docker_ready; then
            return 0
        fi
        sleep 2
    done
    return 1
}

# ---------------------------------------------------------------------------
# Kali imajlari ve konteyner
# ---------------------------------------------------------------------------
build_cli_image() {
    local -a net_args=()
    if (( DOCKER_FALLBACK == 1 )); then
        net_args=(--network=host)
    fi
    log "Kali taban imaji cekiliyor: ${BASE_IMAGE}"
    # Gecici Docker Hub hatalarinda build zaten taban imaji cekecegi icin pull'i zorunlu kilmiyoruz.
    if ! "${DOCKER[@]}" pull "${BASE_IMAGE}"; then
        warn "${BASE_IMAGE} cekilemedi; docker build sirasinda yeniden denenecek."
    fi
    log "Kali terminal imaji olusturuluyor: ${IMAGE} (Dockerfile / cli)"
    "${DOCKER[@]}" build "${net_args[@]}" \
        --file "${ROOT_DIR}/Dockerfile" \
        --tag "${IMAGE}" \
        "${ROOT_DIR}"
}

build_desktop_image() {
    local -a net_args=()
    if (( DOCKER_FALLBACK == 1 )); then
        net_args=(--network=host)
    fi
    log "Kali masaustu imaji olusturuluyor: ${DESKTOP_IMAGE} (Dockerfile / desktop)"
    "${DOCKER[@]}" build "${net_args[@]}" \
        --file "${ROOT_DIR}/Dockerfile" \
        --target desktop \
        --tag "${DESKTOP_IMAGE}" \
        "${ROOT_DIR}"
}

ensure_target_image() {
    if ! "${DOCKER[@]}" image inspect "${TARGET_IMAGE}" >/dev/null 2>&1; then
        if [[ "${DESKTOP}" == "1" ]]; then
            build_desktop_image
        else
            build_cli_image
        fi
    fi
}

create_container() {
    local -a args=(
        --detach
        --name "${CONTAINER}"
        --hostname kali
        --volume "${WORKSPACE}:/workspace"
        --workdir /workspace
    )
    local -a cmd=(tail -f /dev/null)

    if [[ "${DESKTOP}" == "1" ]]; then
        args+=(
            --env "KALI_VNC_PASSWORD=${VNC_PASSWORD}"
            --env "KALI_VNC_RESOLUTION=${RESOLUTION}"
        )
        if (( DOCKER_FALLBACK == 1 )); then
            # Kendi dockerd'imiz bridge/iptables olmadan calisiyor: port yayinlama
            # yerine host agini kullan, servis dogrudan Codespace portuna baglansin.
            args+=(
                --network=host
                --env "KALI_WEB_PORT=${WEB_PORT}"
                --env "KALI_VNC_PORT=${VNC_PORT}"
            )
        else
            args+=(
                --publish "${WEB_PORT}:6080"
                --publish "${VNC_PORT}:5901"
            )
        fi
        cmd=()   # Dockerfile / desktop hedefinin CMD'si (kali-desktop) calissin
    fi

    "${DOCKER[@]}" run "${args[@]}" "${TARGET_IMAGE}" "${cmd[@]}" >/dev/null
}

setup_portainer() {
    if [[ "${PORTAINER}" != "1" ]]; then
        return 0
    fi
    if "${DOCKER[@]}" container inspect "${PORTAINER_CONTAINER}" >/dev/null 2>&1; then
        if [[ "$("${DOCKER[@]}" container inspect -f '{{.State.Running}}' "${PORTAINER_CONTAINER}")" != "true" ]]; then
            "${DOCKER[@]}" start "${PORTAINER_CONTAINER}" >/dev/null
        fi
        return 0
    fi
    local -a net_args=()
    if (( DOCKER_FALLBACK == 1 )); then
        net_args=(--network=host)
    else
        net_args=(--publish "${PORTAINER_PORT}:9443")
    fi
    log "Portainer (Docker web paneli) baslatiliyor: ${PORTAINER_PORT}"
    "${DOCKER[@]}" run \
        --detach \
        --name "${PORTAINER_CONTAINER}" \
        --restart unless-stopped \
        "${net_args[@]}" \
        --volume /var/run/docker.sock:/var/run/docker.sock \
        --volume portainer_data:/data \
        portainer/portainer-ce:latest >/dev/null
}

wait_for_desktop() {
    if [[ "${DESKTOP}" != "1" ]]; then
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        return 0
    fi
    local attempt
    for (( attempt = 1; attempt <= DESKTOP_WAIT_ATTEMPTS; attempt++ )); do
        if curl -fsS -o /dev/null "http://127.0.0.1:${WEB_PORT}/" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    warn "noVNC ${WEB_PORT} portunda henuz yanit vermiyor; 'docker logs ${CONTAINER}' ile kontrol edin."
    return 0
}

# ---------------------------------------------------------------------------
# Ana akis
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    if [[ "${AUTO_INSTALL_DOCKER}" != "1" ]]; then
        warn "Docker CLI yok ve KALI_AUTO_INSTALL_DOCKER=0. 'Kali Masaustu (DinD'siz)' yapilandirmasini deneyin."
        exit 0
    fi
    log "Docker CLI bulunamadi; Docker-in-Docker kuruluyor"
    if ! ensure_docker; then
        warn "Docker-in-Docker kurulamadi. Recovery konteynerinde iseniz .devcontainer/devcontainer.json'u duzeltip 'Codespaces: Rebuild Container' yapin; ya da 'Kali Masaustu (DinD'siz)' yapilandirmasini secin."
        exit 0
    fi
fi

if (( FEATURE_INSTALLED == 0 )) && ! docker_ready; then
    detect_sudo || warn "root/sudo yok; dockerd baslatilamayabilir"
    if ! start_dockerd; then
        warn "Docker-in-Docker daemon baslatilamadi; /tmp/kali-dockerd.log dosyasina bakin."
        exit 0
    fi
    WAIT_ATTEMPTS="${FALLBACK_WAIT_ATTEMPTS}"
fi

if ! wait_for_docker; then
    warn "Docker daemon yaklasik $(( WAIT_ATTEMPTS * 2 )) saniye icinde hazir olmadi. Ayrintilar: /tmp/kali-dockerd.log ve Codespaces creation log."
    exit 0
fi

if (( START_ONLY == 0 )); then
    build_cli_image
    if [[ "${DESKTOP}" == "1" ]]; then
        build_desktop_image
    fi
fi

if "${DOCKER[@]}" container inspect "${CONTAINER}" >/dev/null 2>&1; then
    current_image="$("${DOCKER[@]}" container inspect -f '{{.Config.Image}}' "${CONTAINER}")"
    if [[ "${current_image}" != "${TARGET_IMAGE}" ]]; then
        # Ornegin masaustu sonradan acildiysa / kapatildiysa eski konteyneri yeniden kur.
        log "Konteyner yeniden olusturuluyor (imaj: ${current_image} -> ${TARGET_IMAGE})"
        "${DOCKER[@]}" rm -f "${CONTAINER}" >/dev/null
        ensure_target_image
        create_container
    elif [[ "$("${DOCKER[@]}" container inspect -f '{{.State.Running}}' "${CONTAINER}")" != "true" ]]; then
        log "${CONTAINER} konteyneri yeniden baslatiliyor"
        "${DOCKER[@]}" start "${CONTAINER}" >/dev/null
    else
        log "${CONTAINER} konteyneri zaten calisiyor"
    fi
else
    ensure_target_image
    log "Kali konteyneri olusturuluyor: ${CONTAINER}"
    create_container
fi

setup_portainer

# Codespace icinden `kali` yazarak Kali kabuguna girmek icin kisa yol.
install_kali_command() {
    local helper target
    helper="$(mktemp)"
    cat > "${helper}" <<'KALI_HELPER'
#!/usr/bin/env bash
# Kali konteynerine girer:    kali            -> etkilesimli bash
#                             kali nmap -sV x -> komut calistirir
set -euo pipefail

container="${KALI_CONTAINER:-kali}"
DOCKER=(docker)
if ! docker info >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
fi

if ! "${DOCKER[@]}" container inspect "${container}" >/dev/null 2>&1; then
    echo "Kali konteyneri bulunamadi. Kurulum: bash .devcontainer/setup-kali.sh" >&2
    exit 1
fi
if [[ "$("${DOCKER[@]}" container inspect -f '{{.State.Running}}' "${container}")" != "true" ]]; then
    "${DOCKER[@]}" start "${container}" >/dev/null
fi

tty_flags=(-i)
[[ -t 0 ]] && tty_flags=(-it)

if (( $# == 0 )); then
    exec "${DOCKER[@]}" exec "${tty_flags[@]}" "${container}" /bin/bash
else
    exec "${DOCKER[@]}" exec "${tty_flags[@]}" "${container}" "$@"
fi
KALI_HELPER

    if [[ "$(id -u)" -eq 0 ]]; then
        target="/usr/local/bin/kali"
        install -m 0755 "${helper}" "${target}"
    elif sudo -n true 2>/dev/null; then
        target="/usr/local/bin/kali"
        sudo install -m 0755 "${helper}" "${target}"
    else
        mkdir -p "${HOME}/.local/bin"
        target="${HOME}/.local/bin/kali"
        install -m 0755 "${helper}" "${target}"
        warn "sudo kullanilamadi; 'kali' ${target} konumuna kuruldu (PATH'te oldugundan emin olun)."
    fi
    rm -f "${helper}"
}

install_kali_command
wait_for_desktop

log "Kali hazir!"
printf '  kali                         -> Kali kabugu\n'
printf '  docker exec -it %s bash    -> ayni islem\n' "${CONTAINER}"
printf '  docker ps                    -> calisan konteynerler\n'
if (( DOCKER_FALLBACK == 1 )); then
    printf '  Docker modu                  -> yerel DinD (host network, vfs)\n'
fi
if [[ "${DESKTOP}" == "1" ]]; then
    printf '\n  Masaustu (noVNC) : http://localhost:%s/vnc.html\n' "${WEB_PORT}"
    if [[ -n "${CODESPACE_NAME:-}" ]]; then
        domain="${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}"
        printf '  Codespace URL    : https://%s-%s.%s/vnc.html\n' "${CODESPACE_NAME}" "${WEB_PORT}" "${domain}"
    fi
    printf '  VNC sifresi      : %s\n' "${VNC_PASSWORD:-(yok)}"
    printf '  VNC portu        : %s\n' "${VNC_PORT}"
fi
if [[ "${PORTAINER}" == "1" ]]; then
    printf '  Portainer        : https://localhost:%s\n' "${PORTAINER_PORT}"
fi
