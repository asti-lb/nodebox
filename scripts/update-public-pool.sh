#!/usr/bin/env bash
# Update Public Pool (backend + UI) to the commits pinned in install-public-pool.sh.
# Public Pool has no release versions; NodeBox tracks specific tested commits, so
# "updating" means rebuilding to whatever commits the installer currently pins.
set -euo pipefail

log()  { echo "[+] $*"; }
err()  { echo "[!] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"

INSTALL_DIR="/opt/public-pool"
WEB_DIR="/var/www/pool"
INSTALL_SCRIPT="/opt/nodebox/scripts/install-public-pool.sh"

# The backend repo is owned by 'pool'; running git as root would otherwise be
# refused with "dubious ownership". Whitelist the repo per-call (no global state).
git_safe() {  # usage: git_safe <repo_dir> <git args...>
    git -c safe.directory="$1" -C "$1" "${@:2}"
}

[[ -d "$INSTALL_DIR/backend/.git" ]] || err "Public Pool is not installed."

# Pinned commits live in the install script — single source of truth.
BACKEND_COMMIT=$(grep -m1 '^BACKEND_COMMIT=' "$INSTALL_SCRIPT" | cut -d'"' -f2)
UI_COMMIT=$(grep -m1 '^UI_COMMIT=' "$INSTALL_SCRIPT" | cut -d'"' -f2)
[[ -n "$BACKEND_COMMIT" && -n "$UI_COMMIT" ]] || err "Could not read pinned commits from installer."

CURRENT_BACKEND=$(git_safe "$INSTALL_DIR/backend" rev-parse HEAD)
CURRENT_UI=$(git_safe "$INSTALL_DIR/ui" rev-parse HEAD 2>/dev/null || echo "unknown")

log "Backend: ${CURRENT_BACKEND:0:12} -> ${BACKEND_COMMIT:0:12}"
log "UI:      ${CURRENT_UI:0:12} -> ${UI_COMMIT:0:12}"

if [[ "$CURRENT_BACKEND" == "$BACKEND_COMMIT" && "$CURRENT_UI" == "$UI_COMMIT" ]]; then
    log "Already up to date — nothing to do."
    exit 0
fi

log "Stopping public-pool ..."
systemctl stop public-pool

# ── Backend ─────────────────────────────────────────────────────────────────────
log "Updating backend (commit ${BACKEND_COMMIT:0:12}) ..."
git_safe "$INSTALL_DIR/backend" fetch --quiet origin
git_safe "$INSTALL_DIR/backend" checkout --quiet -f "$BACKEND_COMMIT"
(cd "$INSTALL_DIR/backend" && npm ci --quiet && npm run build --quiet)
chown -R pool:pool "$INSTALL_DIR/backend"

# ── Frontend ────────────────────────────────────────────────────────────────────
log "Updating frontend (commit ${UI_COMMIT:0:12}) ..."
git_safe "$INSTALL_DIR/ui" fetch --quiet origin
git_safe "$INSTALL_DIR/ui" checkout --quiet -f "$UI_COMMIT"

# Re-apply the local environment patch (checkout -f discards it).
cat > "$INSTALL_DIR/ui/src/environments/environment.prod.ts" << 'EOF'
export const environment = {
    production: true,
    API_URL: '/pool',
    STRATUM_URL: 'nodebox.local:3333'
};
EOF

log "Building frontend (this takes a few minutes) ..."
(cd "$INSTALL_DIR/ui" \
    && npm ci --quiet \
    && ./node_modules/.bin/ng build --configuration=production --base-href /pool/)
rsync -a --delete "$INSTALL_DIR/ui/dist/public-pool-ui/" "$WEB_DIR/"
chmod -R 755 "$WEB_DIR"

log "Starting public-pool ..."
systemctl start public-pool

log "Public Pool updated successfully."
