#!/usr/bin/env bash
set -euo pipefail

# NodeBox — Base system setup
# Run once after fresh Debian 13 install, as admin user with sudo.
# Usage: bash setup-base.sh

log()  { echo "[+] $*"; }
err()  { echo "[!] $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || err "Run as admin user (not root): bash $0"

CLAUDE_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDsl9tpGGTKQXSYmjUIZI/f5vHDDdRo67Oz3CAIwUIto claude-code-lernebitcoin"
CLAUDE_IP="192.168.178.51"

# ── 1. System update ──────────────────────────────────────────────────────────

log "Updating system ..."
sudo apt-get update -qq
sudo apt-get full-upgrade -y

log "Installing base packages ..."
sudo apt-get install -y ufw fail2ban curl git wget gnupg

# ── 2. SSH ────────────────────────────────────────────────────────────────────

log "Configuring SSH ..."
sudo sed -i \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin no/' \
    /etc/ssh/sshd_config

# Add Claude's deploy key
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
grep -qF "$CLAUDE_KEY" ~/.ssh/authorized_keys || echo "$CLAUDE_KEY" >> ~/.ssh/authorized_keys

sudo systemctl reload ssh
log "SSH configured — password auth ON, root login OFF"

# ── 3. Firewall ───────────────────────────────────────────────────────────────

log "Configuring UFW ..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    comment "SSH"
sudo ufw allow 443/tcp   comment "HTTPS dashboard"
sudo ufw allow 50001/tcp comment "Fulcrum TCP"
sudo ufw allow 50002/tcp comment "Fulcrum SSL"
sudo ufw --force enable
log "UFW enabled"

# ── 4. fail2ban ───────────────────────────────────────────────────────────────

log "Configuring fail2ban ..."
sudo tee /etc/fail2ban/jail.d/nodebox.conf > /dev/null <<EOF
[sshd]
enabled  = true
maxretry = 5
bantime  = 1h
ignoreip = 127.0.0.1/8 ${CLAUDE_IP}
EOF
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
log "fail2ban configured (${CLAUDE_IP} on ignorelist)"

# ── 5. Service users ──────────────────────────────────────────────────────────

log "Creating service users ..."
for user in bitcoin fulcrum mempool dashboard; do
    if ! id "$user" &>/dev/null; then
        sudo useradd -r -s /usr/sbin/nologin -d /nonexistent "$user"
        log "  Created user: $user"
    else
        log "  User already exists: $user"
    fi
done

sudo usermod -aG bitcoin fulcrum
sudo usermod -aG bitcoin dashboard
sudo usermod -aG systemd-journal dashboard

# ── 6. Directory structure ────────────────────────────────────────────────────

log "Creating directory structure ..."

sudo mkdir -p /data/bitcoin
sudo chown bitcoin:bitcoin /data/bitcoin
sudo chmod 750 /data/bitcoin

sudo mkdir -p /data/fulcrum
sudo chown fulcrum:fulcrum /data/fulcrum
sudo chmod 750 /data/fulcrum

sudo mkdir -p /opt/nodebox/{scripts,dashboard}
sudo chown -R admin:admin /opt/nodebox
sudo chmod 755 /opt/nodebox

log "Directories created"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
log "Base setup complete."
log "Next: run scripts/restore-blockchain.sh to copy blockchain from sda backup."
