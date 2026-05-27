#!/bin/sh

set -eu

IMAGE_URL="https://raw.githubusercontent.com/LaryHUB/rush/main/rssh-amd64.tar"

SSH_USER="skai"
SSH_PORT="2222"

PASSWORD=$(openssl rand -base64 18 | tr -d "=+/")

log() {
    printf '\033[1;34m[rssh]\033[0m %s\n' "$*"
}

err() {
    printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || err "run as root or via sudo"

# install docker if missing
if ! command -v docker >/dev/null 2>&1; then
    log "installing docker"

    if ! command -v curl >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y -qq curl ca-certificates >/dev/null
    fi

    curl -fsSL https://get.docker.com | sh

    systemctl enable --now docker 2>/dev/null || \
    service docker start 2>/dev/null || true
fi

docker info >/dev/null 2>&1 || err "docker daemon not running"

log "downloading rssh image"

mkdir -p /opt/rssh
cd /opt/rssh

curl -L "$IMAGE_URL" -o rssh-amd64.tar

log "loading image"

docker load -i rssh-amd64.tar >/dev/null

docker rm -f rssh >/dev/null 2>&1 || true

log "starting rssh"

docker run -d \
    --restart unless-stopped \
    --name rssh \
    -e SSH_PASSWORD="$PASSWORD" \
    -p ${SSH_PORT}:22 \
    -p 4400-4499:4400-4499 \
    rssh-amd64 >/dev/null

HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$HOST_IP" ] && HOST_IP=$(hostname)

echo ""
echo "=================================="
echo " RSSH READY"
echo "=================================="
echo ""
echo "Server host ${HOST_IP}:${SSH_PORT}"
echo "Server Port 44XX"
echo "Server User ${SSH_USER}"
echo "Server Password ${PASSWORD}"
echo ""
