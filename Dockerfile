# Kali Linux image used by:
#   * .github/workflows/docker-image.yml    (CI build, default = cli hedefi)
#   * .github/workflows/docker-publish.yml  (GHCR publish, default = cli hedefi)
#   * .devcontainer/setup-kali.sh           (Codespace acildiginda `docker build`)
#
# Hedefler:
#   base    -> ortak Kali arac seti
#   cli     -> sadece terminal (varsayilan / son stage, CI bunu build eder)
#   desktop -> cli + XFCE + Xvfb + x11vnc + noVNC (6080 portunda web masaustu)
ARG KALI_BASE_IMAGE=kalilinux/kali-rolling
FROM ${KALI_BASE_IMAGE} AS base

ENV DEBIAN_FRONTEND=noninteractive

# Varsayilan olarak hafif bir Kali arac seti kurulur. Daha fazlasi icin:
#   docker build --build-arg KALI_PACKAGES="kali-linux-headless" -t kali-docker .
ARG KALI_PACKAGES="ca-certificates curl wget git sudo iputils-ping net-tools procps python3 python3-pip nmap netcat-openbsd tcpdump dnsutils whois hydra john sqlmap nikto dirb"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ${KALI_PACKAGES} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# --- Grafik masaustu hedefi -------------------------------------------------
FROM base AS desktop

ENV DISPLAY=:99 \
    KALI_VNC_RESOLUTION=1280x800x24

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        xfce4 xfce4-terminal dbus-x11 \
        xvfb x11vnc novnc websockify \
        x11-utils xfonts-base fonts-dejavu-core \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && printf '%s\n' '<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&amp;resize=scale"></head><body><a href="vnc.html?autoconnect=true&amp;resize=scale">Kali masaustu</a></body></html>' > /usr/share/novnc/index.html

COPY kali-desktop.sh /usr/local/bin/kali-desktop
RUN chmod 0755 /usr/local/bin/kali-desktop

EXPOSE 6080 5901
CMD ["/usr/local/bin/kali-desktop"]

# --- Varsayilan hedef (son stage): CI ve CLI kullanim ----------------------
FROM base AS cli
CMD ["/bin/bash"]
