#!/usr/bin/env bash
#
# Kali XFCE masaustunu baslatir:
#   Xvfb (:99) -> startxfce4 -> x11vnc (:5901) -> websockify/noVNC (0.0.0.0:6080)
#
# Dockerfile'in `desktop` hedefinde CMD olarak calisir. Tarayicidan
# http://localhost:6080/vnc.html (Codespace'te forward edilen 6080 portu) ile ulasilir.
#
# Ortam degiskenleri:
#   KALI_VNC_PASSWORD      VNC/noVNC sifresi (bos ise sifresiz)
#   KALI_VNC_RESOLUTION    Xvfb ekran cozunurlugu (ornek: 1920x1080x24)
#   KALI_VNC_PORT          x11vnc portu (5901)
#   KALI_WEB_PORT          noVNC web portu (6080)
#   KALI_NOVNC_WEB         noVNC web kok dizini (/usr/share/novnc)

set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
RESOLUTION="${KALI_VNC_RESOLUTION:-1280x800x24}"
VNC_PORT="${KALI_VNC_PORT:-5901}"
WEB_PORT="${KALI_WEB_PORT:-6080}"
NOVNC_WEB="${KALI_NOVNC_WEB:-/usr/share/novnc}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/kali-xdg}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"

pids=()
cleanup() {
    trap - EXIT INT TERM
    for pid in "${pids[@]}"; do
        kill "${pid}" 2>/dev/null || true
    done
}
trap cleanup EXIT INT TERM

# 1) Sanal X ekrani
Xvfb "${DISPLAY}" -screen 0 "${RESOLUTION}" -ac -nolisten tcp \
    +extension GLX +render -noreset >/tmp/kali-xvfb.log 2>&1 &
pids+=("$!")
x_socket="/tmp/.X11-unix/X${DISPLAY#:}"
for _ in {1..50}; do
    [[ -S "${x_socket}" ]] && break
    sleep 0.2
done
if [[ ! -S "${x_socket}" ]]; then
    echo "Xvfb baslatilamadi:" >&2
    cat /tmp/kali-xvfb.log >&2
    exit 1
fi

# 2) VNC sunucusu (sifre opsiyonel; VNC protokolu en fazla 8 karakter kullanir)
# x11vnc varsayilan olarak tum arayuzleri dinler (-localhost ile kisitlanabilir).
vnc_args=(-forever -shared -display "${DISPLAY}" -rfbport "${VNC_PORT}")
if [[ -n "${KALI_VNC_PASSWORD:-}" ]]; then
    x11vnc -storepasswd "${KALI_VNC_PASSWORD}" /tmp/kali-vnc-passwd >/dev/null 2>&1
    vnc_args+=(-rfbauth /tmp/kali-vnc-passwd)
else
    vnc_args+=(-nopw)
fi
x11vnc "${vnc_args[@]}" >/tmp/kali-x11vnc.log 2>&1 &
pids+=("$!")

# 3) XFCE oturumu
if command -v dbus-launch >/dev/null 2>&1; then
    dbus-launch --exit-with-session startxfce4 >/tmp/kali-xfce.log 2>&1 &
else
    startxfce4 >/tmp/kali-xfce.log 2>&1 &
fi
pids+=("$!")

# 4) noVNC websocket korusu: 0.0.0.0:6080 -> localhost:5901
printf 'Kali masaustu hazir: http://0.0.0.0:%s/  (VNC %s)\n' "${WEB_PORT}" "${VNC_PORT}"
websockify --web "${NOVNC_WEB}" "0.0.0.0:${WEB_PORT}" "localhost:${VNC_PORT}" &
pids+=("$!")

wait "${pids[${#pids[@]} - 1]}"
