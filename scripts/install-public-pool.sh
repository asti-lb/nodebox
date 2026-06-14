#!/bin/bash
# install-public-pool.sh — installs Public Pool solo mining pool
# Run with: sudo bash /opt/nodebox/scripts/install-public-pool.sh

set -euo pipefail

# Pinned commits (tested with NodeBox)
BACKEND_COMMIT="b971e9ce4ccd23ae98536d57dcf63657ade7919f"
UI_COMMIT="1c0b2d93e3ce0a81d4faa7b1d444ace936e3f63d"

INSTALL_DIR="/opt/public-pool"
DATA_DIR="/data/pool"
WEB_DIR="/var/www/pool"
STRATUM_PORT=3333
API_PORT=3334
ZMQ_PORT=8434

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# On re-runs the backend repo is owned by 'pool'; running git as root would be
# refused with "dubious ownership". Whitelist the repo per-call (no global state).
git_safe() {  # usage: git_safe <repo_dir> <git args...>
    git -c safe.directory="$1" -C "$1" "${@:2}"
}

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo." >&2
    exit 1
fi

# ── 1. System user ─────────────────────────────────────────────────────────────
log "Setting up system user 'pool'..."
if ! id pool &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin pool
fi
usermod -aG bitcoin pool  # needs to read the RPC cookie

# ── 2. ZMQ rawblock (required by public-pool for new block notifications) ──────
BITCOIN_CONF="/data/bitcoin/bitcoin.conf"
if ! grep -q "zmqpubrawblock" "$BITCOIN_CONF"; then
    log "Adding zmqpubrawblock to bitcoin.conf (port ${ZMQ_PORT})..."
    echo "zmqpubrawblock=tcp://127.0.0.1:${ZMQ_PORT}" >> "$BITCOIN_CONF"
    log "Restarting bitcoind..."
    systemctl restart bitcoind
    sleep 10
    log "bitcoind restarted."
else
    log "zmqpubrawblock already configured."
fi

# ── 3. Backend ─────────────────────────────────────────────────────────────────
log "Installing backend (commit ${BACKEND_COMMIT:0:12})..."
mkdir -p "$INSTALL_DIR"

if [ -d "$INSTALL_DIR/backend/.git" ]; then
    log "Backend repo exists, updating..."
    git_safe "$INSTALL_DIR/backend" fetch --quiet origin
else
    git clone --quiet https://github.com/benjamin-wilson/public-pool "$INSTALL_DIR/backend"
fi
git_safe "$INSTALL_DIR/backend" checkout --quiet "$BACKEND_COMMIT"

cd "$INSTALL_DIR/backend"
npm ci --quiet
npm run build --quiet

# .env config
cat > "$INSTALL_DIR/backend/.env" << EOF
BITCOIN_RPC_URL=http://127.0.0.1
BITCOIN_RPC_PORT=8332
BITCOIN_RPC_COOKIEFILE=/data/bitcoin/.cookie
BITCOIN_ZMQ_HOST=tcp://127.0.0.1:${ZMQ_PORT}
API_PORT=${API_PORT}
STRATUM_PORT=${STRATUM_PORT}
NETWORK=mainnet
API_SECURE=false
POOL_IDENTIFIER=NodeBox
DEV_FEE_ADDRESS=
EOF

# SQLite data directory, symlinked into the app working directory
mkdir -p "$DATA_DIR"
if [ ! -L "$INSTALL_DIR/backend/DB" ]; then
    ln -sf "$DATA_DIR" "$INSTALL_DIR/backend/DB"
fi

chown -R pool:pool "$INSTALL_DIR/backend"
chown -R pool:pool "$DATA_DIR"

# ── 4. Frontend ────────────────────────────────────────────────────────────────
log "Installing frontend (commit ${UI_COMMIT:0:12})..."

if [ -d "$INSTALL_DIR/ui/.git" ]; then
    log "UI repo exists, updating..."
    git_safe "$INSTALL_DIR/ui" fetch --quiet origin
else
    git clone --quiet https://github.com/benjamin-wilson/public-pool-ui "$INSTALL_DIR/ui"
fi
git_safe "$INSTALL_DIR/ui" checkout --quiet "$UI_COMMIT"

cd "$INSTALL_DIR/ui"
npm ci --quiet

# Patch environment to use our local nginx path instead of public-pool.io
cat > src/environments/environment.prod.ts << 'EOF'
export const environment = {
    production: true,
    API_URL: '/pool',
    STRATUM_URL: 'nodebox.local:3333'
};
EOF

log "Building frontend (this takes a few minutes)..."
# Run ng build directly to skip the gzipper step; nginx handles compression
./node_modules/.bin/ng build --configuration=production --base-href /pool/

mkdir -p "$WEB_DIR"
rsync -a --delete dist/public-pool-ui/ "$WEB_DIR/"
chmod -R 755 "$WEB_DIR"

# ── 5. Nginx ───────────────────────────────────────────────────────────────────
log "Updating nginx config..."
python3 - << 'PYEOF'
POOL_LOCATIONS = """\
    # Public Pool — web UI and API
    location = /pool { return 302 /pool/; }
    location /pool/api/ {
        proxy_pass         http://127.0.0.1:3334/api/;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
    }
    location /pool/ {
        alias              /var/www/pool/;
        try_files          $uri $uri/ /pool/index.html;
    }

"""
NGINX_CONF = "/etc/nginx/sites-available/nodebox"
with open(NGINX_CONF) as f:
    config = f.read()
if "/pool/" not in config:
    config = config.replace(
        "    # Dashboard (root",
        POOL_LOCATIONS + "    # Dashboard (root"
    )
    with open(NGINX_CONF, "w") as f:
        f.write(config)
    print("Nginx config updated.")
else:
    print("Nginx /pool/ location already present.")
PYEOF

nginx -t && systemctl reload nginx

# ── 6. Firewall ────────────────────────────────────────────────────────────────
log "Opening Stratum port ${STRATUM_PORT} for local network..."
ufw allow from 192.168.0.0/16 to any port "$STRATUM_PORT" proto tcp comment 'Public Pool Stratum (LAN)' 2>/dev/null || true

# ── 7. systemd ─────────────────────────────────────────────────────────────────
log "Enabling public-pool service..."
cp /opt/nodebox/services/public-pool.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now public-pool

log ""
log "Installation complete."
log "  Web UI:   https://nodebox.local/pool/"
log "  Stratum:  stratum+tcp://nodebox.local:${STRATUM_PORT}"
log ""
log "Configure your miner to connect to: nodebox.local:${STRATUM_PORT}"
log "Use your Bitcoin address as username, anything as password."
