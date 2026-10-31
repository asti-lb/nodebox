#!/usr/bin/env bash
# Update Bitcoin Core to the version NodeBox has tested (configs/bitcoin-core-version).
# Downloads the binary, verifies GPG signatures and SHA256 checksum,
# then replaces the running binary with zero manual steps.
set -euo pipefail

log()  { echo "[+] $*"; }
err()  { echo "[!] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"

INSTALL_DIR="/usr/local/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── Check version ─────────────────────────────────────────────────────────────

VERSION=$(cat /opt/nodebox/configs/bitcoin-core-version)
[[ -n "$VERSION" ]] || err "Could not determine target version."

CURRENT=$(bitcoind --version 2>/dev/null | grep -oP '\d+\.\d+(\.\d+)?' | head -1 || true)
CURRENT=${CURRENT%.0}   # bitcoind reports 31.2.0 for release 31.2
log "Installed: ${CURRENT:-unknown}  →  Target: ${VERSION}"
[[ "$CURRENT" == "$VERSION" ]] && { log "Already up to date."; exit 0; }

# ── Download ──────────────────────────────────────────────────────────────────

ARCH="x86_64-linux-gnu"
BASE="bitcoin-${VERSION}-${ARCH}"
URL="https://bitcoincore.org/bin/bitcoin-core-${VERSION}"

log "Downloading ${BASE}.tar.gz ..."
curl -fsSL --progress-bar -o "$TMP/${BASE}.tar.gz"     "${URL}/${BASE}.tar.gz"
curl -fsSL -o "$TMP/SHA256SUMS"                        "${URL}/SHA256SUMS"
curl -fsSL -o "$TMP/SHA256SUMS.asc"                    "${URL}/SHA256SUMS.asc"

# ── GPG verification ──────────────────────────────────────────────────────────

# A keyring of its own, so only the release signers in the repo count as valid.
export GNUPGHOME="$TMP/gnupg"
install -d -m 0700 "$GNUPGHOME"

log "Importing Bitcoin Core release signing keys ..."
gpg --import /opt/nodebox/configs/bitcoin-core-keys.asc 2>/dev/null

# gpg exits non-zero when any signer's key is missing, so count good signatures instead.
log "Verifying GPG signatures ..."
GOOD=$(gpg --status-fd 1 --verify "$TMP/SHA256SUMS.asc" "$TMP/SHA256SUMS" 2>/dev/null \
  | grep -c '^\[GNUPG:\] GOODSIG' || true)
log "Good signatures from known keys: ${GOOD}"
[[ "$GOOD" -ge 3 ]] || err "GPG verification failed: need at least 3 good signatures."

# ── SHA256 verification ───────────────────────────────────────────────────────

log "Verifying SHA256 checksum ..."
(cd "$TMP" && grep "${BASE}.tar.gz" SHA256SUMS | sha256sum -c --strict) \
  || err "SHA256 checksum mismatch."

# ── Install ───────────────────────────────────────────────────────────────────

log "Extracting and installing binaries ..."
tar -xzf "$TMP/${BASE}.tar.gz" -C "$TMP"
install -m 0755 "$TMP/${BASE}/bin/bitcoind"   "$INSTALL_DIR/bitcoind"
install -m 0755 "$TMP/${BASE}/bin/bitcoin-cli" "$INSTALL_DIR/bitcoin-cli"

log "Restarting bitcoind ..."
systemctl restart bitcoind

log "Bitcoin Core ${VERSION} installed successfully."
