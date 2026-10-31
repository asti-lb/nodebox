#!/usr/bin/env bash
# Restart the machine. All services shut down cleanly first.
set -euo pipefail

echo "[+] Restarting. Shutdown can take up to 10 minutes, then reload this page."
systemctl reboot
