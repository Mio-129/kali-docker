# Kali Linux image used by:
#   * .github/workflows/docker-image.yml   (CI build)
#   * .github/workflows/docker-publish.yml (GHCR publish)
#   * .devcontainer/setup-kali.sh          (Codespace acildiginda `docker build`)
FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# Varsayilan olarak hafif bir Kali arac seti kurulur. Daha fazlasi icin:
#   docker build --build-arg KALI_PACKAGES="kali-linux-headless" -t kali-docker .
ARG KALI_PACKAGES="ca-certificates curl wget git sudo iputils-ping net-tools procps python3 python3-pip nmap netcat-openbsd tcpdump dnsutils whois hydra john sqlmap nikto dirb"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ${KALI_PACKAGES} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["/bin/bash"]
