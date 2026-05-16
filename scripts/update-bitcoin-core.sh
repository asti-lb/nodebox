#!/usr/bin/env bash
# Update Bitcoin Core to the latest release.
# Downloads the binary, verifies GPG signature and SHA256 checksum,
# then replaces the running binary with zero manual steps.
set -euo pipefail

log()  { echo "[+] $*"; }
err()  { echo "[!] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"

INSTALL_DIR="/usr/local/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── Fetch latest release ──────────────────────────────────────────────────────

log "Fetching latest Bitcoin Core release from GitHub ..."
LATEST=$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/bitcoin/bitcoin/releases/latest" \
  | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')

[[ -n "$LATEST" ]] || err "Could not determine latest version."

CURRENT=$(bitcoind --version 2>/dev/null | grep -oP '\d+\.\d+(\.\d+)?' | head -1 || true)
log "Installed: ${CURRENT:-unknown}  →  Latest: ${LATEST}"
[[ "$CURRENT" == "$LATEST" ]] && { log "Already up to date."; exit 0; }

# ── Download ──────────────────────────────────────────────────────────────────

ARCH="x86_64-linux-gnu"
BASE="bitcoin-${LATEST}-${ARCH}"
URL="https://bitcoincore.org/bin/bitcoin-core-${LATEST}"

log "Downloading ${BASE}.tar.gz ..."
curl -fsSL --progress-bar -o "$TMP/${BASE}.tar.gz"     "${URL}/${BASE}.tar.gz"
curl -fsSL -o "$TMP/SHA256SUMS"                        "${URL}/SHA256SUMS"
curl -fsSL -o "$TMP/SHA256SUMS.asc"                    "${URL}/SHA256SUMS.asc"

# ── GPG verification ──────────────────────────────────────────────────────────

log "Importing Bitcoin Core release signing keys ..."
gpg --keyserver hkps://keys.openpgp.org --recv-keys \
  E777299FC265DD04793070EB944D35F9AC3DB76A \
  152812300785C96444D3334D17565732E08E5E41 \
  0AD83877C1F0CD1EE9BD660AD7CC770B81FD22A8 \
  590B7292695AFFA5B672CBB2E13FC145CD3F4304 \
  2>/dev/null || true

log "Verifying GPG signature ..."
gpg --verify "$TMP/SHA256SUMS.asc" "$TMP/SHA256SUMS" \
  || err "GPG signature verification failed."

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

log "Bitcoin Core ${LATEST} installed successfully."
