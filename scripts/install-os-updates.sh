#!/usr/bin/env bash
#
# install-os-updates.sh — refresh Debian's package lists daily and install security
# updates automatically, without ever rebooting on its own. Idempotent: safe to run
# repeatedly. Run with sudo.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Refreshing package lists"
apt-get -q update

echo "==> Installing unattended-upgrades"
apt-get -q -y install unattended-upgrades

echo "==> Enabling daily package lists and security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF

echo "==> Done. Active settings:"
apt-config dump | grep -E 'APT::Periodic::(Update-Package-Lists|Unattended-Upgrade) |Unattended-Upgrade::Automatic-Reboot '
