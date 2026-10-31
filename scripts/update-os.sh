#!/usr/bin/env bash
# Install all pending Debian updates. Locally changed config files are kept.
set -euo pipefail

log()  { echo "[+] $*"; }
err()  { echo "[!] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"

export DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none
APT=(apt-get -q -o DPkg::Lock::Timeout=600)

log "Finishing any interrupted package installation ..."
dpkg --configure -a

log "Refreshing package lists ..."
"${APT[@]}" update

# full-upgrade, not upgrade: a new kernel is a new package and would be held back.
log "Installing updates ..."
"${APT[@]}" -y \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold \
  full-upgrade

log "Updates installed."
