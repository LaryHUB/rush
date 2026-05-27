#!/bin/bash

set -e

#IMAGE_URL="https://github.com/LaryHUB/rush/blob/main/rssh.tar"
IMAGE_URL="https://github.com/LaryHUB/rush/raw/main/rssh.tar"

SSH_USER="skai"
SSH_PORT="2222"

PASSWORD=$(openssl rand -base64 18 | tr -d "=+/")

SERVER_IP=$(curl -s https://api.ipify.org)

apt update

apt install -y \
    docker.io \
    curl \
    openssl

systemctl enable docker
systemctl start docker

mkdir -p /opt/rssh

cd /opt/rssh

curl -L "$IMAGE_URL" -o rssh.tar

docker load -i rssh.tar

docker rm -f rssh 2>/dev/null || true

docker run -d \
  --restart unless-stopped \
  --name rssh \
  -e SSH_PASSWORD="$PASSWORD" \
  -p ${SSH_PORT}:22 \
  -p 4400-4499:4400-4499 \
  rssh

echo ""
echo "=================================="
echo " RSSH READY"
echo "=================================="
echo ""
echo "Server host ${SERVER_IP}:${SSH_PORT}"
echo "Server Port 44XX"
echo "Server User ${SSH_USER}"
echo "Server Password ${PASSWORD}"
echo ""
