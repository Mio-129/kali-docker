#!/usr/bin/env bash
#
# GitHub Codespaces acildiginda (postCreateCommand) Docker komutlariyla Kali Linux'u kurar:
#   1. docker pull  -> Kali taban imaji
#   2. docker build -> depodaki Dockerfile'dan yerel Kali imaji
#   3. docker run   -> calisan, calisma alanini goren Kali konteyneri
#   4. `kali`       -> konteynere giren kisa yol komutu
#
# Kullanim:
#   bash .devcontainer/setup-kali.sh               # ilk kurulum (postCreateCommand)
#   bash .devcontainer/setup-kali.sh --start-only  # yeniden baslatma (postStartCommand)
#
# Ortam degiskenleri:
#   KALI_IMAGE      yerel imaj adi            (varsayilan: kali-docker:local)
#   KALI_CONTAINER  konteyner adi            (varsayilan: kali)
#   KALI_WORKSPACE  konteynere baglanan dizin (varsayilan: repo koku)
#   KALI_DOCKER_WAIT_ATTEMPTS  daemon icin 2 saniyelik deneme sayisi (varsayilan: 45)

set -euo pipefail

START_ONLY=0
if [[ "${1:-}" == "--start-only" ]]; then
    START_ONLY=1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_IMAGE="kalilinux/kali-rolling"
IMAGE="${KALI_IMAGE:-kali-docker:local}"
CONTAINER="${KALI_CONTAINER:-kali}"
WORKSPACE="${KALI_WORKSPACE:-$ROOT_DIR}"
DOCKER=(docker)
WAIT_ATTEMPTS="${KALI_DOCKER_WAIT_ATTEMPTS:-45}"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '(!) %s\n' "$*" >&2; }

# Docker-in-Docker daemon'i konteyner acilisinda baslar; hazir olmasini bekle.
# Bazi Codespace'lerde docker soketi icin sudo gerekir, o durumda sudo ile devam et.
wait_for_docker() {
    local attempt
    for (( attempt = 1; attempt <= WAIT_ATTEMPTS; attempt++ )); do
        if docker info >/dev/null 2>&1; then
            return 0
        fi
        if sudo -n true 2>/dev/null && sudo -n docker info >/dev/null 2>&1; then
            DOCKER=(sudo docker)
            return 0
        fi
        sleep 2
    done
    return 1
}

build_image() {
    log "Kali taban imaji cekiliyor: ${BASE_IMAGE}"
    # Gecici Docker Hub hatalarinda build zaten taban imaji cekecegi icin pull'i zorunlu kilmiyoruz.
    if ! "${DOCKER[@]}" pull "${BASE_IMAGE}"; then
        warn "${BASE_IMAGE} cekilemedi; docker build sirasinda yeniden denenecek."
    fi
    log "Kali imaji olusturuluyor: ${IMAGE} (Dockerfile)"
    "${DOCKER[@]}" build --file "${ROOT_DIR}/Dockerfile" --tag "${IMAGE}" "${ROOT_DIR}"
}

if ! command -v docker >/dev/null 2>&1; then
    warn "docker CLI bulunamadi. 'Kali Linux (dogrudan)' yapilandirmasini kullanin veya Docker-in-Docker ozelligini etkinlestirin."
    exit 0
fi

if ! wait_for_docker; then
    warn "Docker daemon yaklasik $(( WAIT_ATTEMPTS * 2 )) saniye icinde hazir olmadi. Codespace yeniden baslatildiginda tekrar denenecek; elle denemek icin: bash .devcontainer/setup-kali.sh"
    exit 0
fi

if (( START_ONLY == 0 )); then
    build_image
fi

if "${DOCKER[@]}" container inspect "${CONTAINER}" >/dev/null 2>&1; then
    if [[ "$("${DOCKER[@]}" container inspect -f '{{.State.Running}}' "${CONTAINER}")" != "true" ]]; then
        log "${CONTAINER} konteyneri yeniden baslatiliyor"
        "${DOCKER[@]}" start "${CONTAINER}" >/dev/null
    else
        log "${CONTAINER} konteyneri zaten calisiyor"
    fi
else
    # postStart sirasinda imaj (Docker volume'u sifirlandiysa) yoksa yeniden kur.
    if ! "${DOCKER[@]}" image inspect "${IMAGE}" >/dev/null 2>&1; then
        build_image
    fi
    log "Kali konteyneri olusturuluyor: ${CONTAINER}"
    "${DOCKER[@]}" run --detach \
        --name "${CONTAINER}" \
        --hostname kali \
        --volume "${WORKSPACE}:/workspace" \
        --workdir /workspace \
        "${IMAGE}" \
        tail -f /dev/null >/dev/null
fi

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

log "Kali hazir!"
printf '  kali                         -> Kali kabugu\n'
printf '  docker exec -it %s bash    -> ayni islem\n' "${CONTAINER}"
printf '  docker ps                    -> calisan konteynerler\n'
