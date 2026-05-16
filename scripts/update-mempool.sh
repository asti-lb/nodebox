#!/usr/bin/env bash
# Update mempool.space to the latest release.
set -euo pipefail

log()  { echo "[+] $*"; }
err()  { echo "[!] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"

MEMPOOL_DIR="/opt/mempool"

# ── Fetch latest version ──────────────────────────────────────────────────────

log "Fetching latest mempool.space release ..."
LATEST=$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/mempool/mempool/releases/latest" \
  | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')

[[ -n "$LATEST" ]] || err "Could not determine latest version."

CURRENT=$(git -C "$MEMPOOL_DIR" describe --tags 2>/dev/null || echo "unknown")
log "Installed: ${CURRENT}  →  Latest: v${LATEST}"

# ── Update ────────────────────────────────────────────────────────────────────

log "Pulling latest changes ..."
git -C "$MEMPOOL_DIR" fetch --tags
git -C "$MEMPOOL_DIR" checkout "v${LATEST}"

log "Stopping mempool-backend ..."
systemctl stop mempool-backend

log "Building backend ..."
(cd "$MEMPOOL_DIR/backend" && npm install --omit=dev && npm run build)

log "Building frontend ..."
(cd "$MEMPOOL_DIR/frontend" && npm install --omit=dev && npm run build -- --base-href /mempool/)

log "Deploying frontend ..."
rsync -a --delete "$MEMPOOL_DIR/frontend/dist/mempool-frontend/" /var/www/mempool/

log "Starting mempool-backend ..."
systemctl start mempool-backend

log "mempool.space ${LATEST} updated successfully."
