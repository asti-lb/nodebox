#!/usr/bin/env bash
#
# install-mempool-watchdog.sh — install the mempool stall watchdog + timer and
# make journald retain logs, so a future stall is caught within minutes (and its
# cause stays readable). Idempotent: safe to run repeatedly. Run with sudo.
set -euo pipefail

REPO="/opt/nodebox"
SYSTEMD="/etc/systemd/system"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

echo "==> Installing mempool watchdog units"
chmod 0755 "$REPO/scripts/mempool-watchdog.sh"
cp "$REPO/services/mempool-watchdog.service" "$SYSTEMD/mempool-watchdog.service"
cp "$REPO/services/mempool-watchdog.timer"   "$SYSTEMD/mempool-watchdog.timer"

echo "==> Making journald logs persistent (so the next stall's cause is readable)"
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/nodebox.conf <<'CONF'
# NodeBox: keep enough log history to diagnose service stalls after the fact.
[Journal]
Storage=persistent
SystemMaxUse=500M
MaxRetentionSec=30day
CONF
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal >/dev/null 2>&1 || true
systemctl restart systemd-journald

echo "==> Enabling watchdog timer"
systemctl daemon-reload
systemctl enable --now mempool-watchdog.timer

echo "==> Done. Timer status:"
systemctl status mempool-watchdog.timer --no-pager --lines=0 || true
echo
echo "Next scheduled run:"
systemctl list-timers mempool-watchdog.timer --no-pager || true
