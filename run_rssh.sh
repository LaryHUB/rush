#!/bin/sh
set -eu

log()  { printf '\033[1;34m[rssh]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }

# ==================== Pre-flight ====================

[ "$(id -u)" -eq 0 ] || err "run as root or via sudo"

command -v sshd     >/dev/null 2>&1 || err "sshd not found — apt-get install openssh-server"
command -v sed      >/dev/null 2>&1 || err "sed not found"
command -v openssl  >/dev/null 2>&1 || err "openssl not found — apt-get install openssl"
command -v ss       >/dev/null 2>&1 || err "ss not found — apt-get install iproute2"

SSHD_CONFIG="/etc/ssh/sshd_config"
[ -f "$SSHD_CONFIG" ] || err "sshd_config not found at $SSHD_CONFIG"

SSH_USER="skai"
SSH_PORT="22"
FWD_PORTS="4400-4499"

log "INFO: $(sshd -V 2>&1 | head -1)"

# ==================== Создание юзера ====================

PASSWORD=$(openssl rand -base64 18 | tr -d "=+/")

if id "$SSH_USER" >/dev/null 2>&1; then
    log "user $SSH_USER already exists — updating password"
else
    useradd -m -s /bin/bash "$SSH_USER" || err "failed to create user $SSH_USER"
    log "created user: $SSH_USER"
fi

echo "${SSH_USER}:${PASSWORD}" | chpasswd || err "failed to set password for $SSH_USER"
log "password set for $SSH_USER"

# ==================== Проверка портов ====================

check_port() {
    PORT="$1"
    if ss -tlnH 2>/dev/null | grep -q ":${PORT} "; then
        log "INFO: port $PORT — listening"
    else
        warn "WARN: port $PORT — not listening yet (will be after sshd reload)"
    fi
}

check_port "$SSH_PORT"

# проверяем не заблокированы ли порты forwarding через iptables
if command -v iptables >/dev/null 2>&1; then
    if iptables -L INPUT -n 2>/dev/null | grep -qE "DROP|REJECT"; then
        warn "WARN: iptables has DROP/REJECT rules — check that ports $FWD_PORTS are allowed"
    else
        log "INFO: iptables INPUT — no blocking rules"
    fi
fi

# ==================== Patch sshd_config ====================

patch_option() {
    KEY="$1"
    VAL="$2"
    if grep -qE "^#?[[:space:]]*${KEY}[[:space:]]" "$SSHD_CONFIG"; then
        sed -i "s|^#\?[[:space:]]*${KEY}[[:space:]].*|${KEY} ${VAL}|" "$SSHD_CONFIG"
    else
        echo "${KEY} ${VAL}" >> "$SSHD_CONFIG"
    fi
    log "set: ${KEY} ${VAL}"
}

patch_option "AllowTcpForwarding"  "yes"
patch_option "GatewayPorts"        "yes"
patch_option "PermitListen"        "any"
patch_option "TCPKeepAlive"        "yes"
patch_option "ClientAliveInterval" "3"
patch_option "ClientAliveCountMax" "2"

if [ -f /etc/pam.d/sshd ]; then
    sed -i 's/^session.*pam_loginuid.so/#&/' /etc/pam.d/sshd
    log "patched: pam_loginuid disabled"
fi

# ==================== Reload ====================

sshd -t 2>&1 || err "sshd_config validation failed — check $SSHD_CONFIG"

if command -v systemctl >/dev/null 2>&1 && systemctl is-active ssh >/dev/null 2>&1; then
    systemctl reload ssh
elif command -v systemctl >/dev/null 2>&1 && systemctl is-active sshd >/dev/null 2>&1; then
    systemctl reload sshd
elif command -v service >/dev/null 2>&1; then
    service ssh reload 2>/dev/null || service sshd reload 2>/dev/null \
        || err "could not reload sshd"
else
    kill -HUP "$(pgrep -x sshd | head -1)" || err "cannot reload sshd"
fi

# ==================== Done ====================

SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo ""
echo "=================================="
echo " RSSH READY"
echo "=================================="
echo ""
if [ "$SSH_PORT" = "22" ]; then
    echo " Host     ${SERVER_IP}"
else
    echo " Host     ${SERVER_IP}:${SSH_PORT}"
fi
echo " Ports    ${FWD_PORTS}"
echo " User     ${SSH_USER}"
echo " Password ${PASSWORD}"
echo ""
