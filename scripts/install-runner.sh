#!/usr/bin/env bash
#
# install-runner.sh — install the task runner that executes dashboard updates and
# installs, and remove the dashboard's sudo rule it replaces. Idempotent: safe to
# run repeatedly. Run with sudo.
set -euo pipefail

REPO="/opt/nodebox"
SYSTEMD="/etc/systemd/system"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

echo "==> Creating request directory"
install -d -m 0755 /var/lib/nodebox
install -d -m 0770 -g dashboard /var/lib/nodebox/requests

echo "==> Installing runner units"
cp "$REPO/services/nodebox-runner.service" "$SYSTEMD/nodebox-runner.service"
cp "$REPO/services/nodebox-runner.path"    "$SYSTEMD/nodebox-runner.path"
systemctl daemon-reload
systemctl enable --now nodebox-runner.path

echo "==> Removing the dashboard's sudo rule (no longer used)"
rm -f /etc/sudoers.d/dashboard

echo "==> Restarting dashboard"
systemctl restart nodebox-dashboard

echo "==> Done."
systemctl status nodebox-runner.path --no-pager --lines=0 || true
