#!/usr/bin/env bash
# Update Fulcrum to the latest release.
set -euo pipefail

log()  { echo "[+] $*"; }
err()  { echo "[!] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"

INSTALL_DIR="/usr/local/bin"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── Fetch latest release ──────────────────────────────────────────────────────

log "Fetching latest Fulcrum release from GitHub ..."
RELEASE=$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/cculianu/Fulcrum/releases/latest")

LATEST=$(echo "$RELEASE" | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
[[ -n "$LATEST" ]] || err "Could not determine latest version."

CURRENT=$(fulcrum --version 2>/dev/null | grep -oP '\d+\.\d+(\.\d+)?' | head -1 || true)
log "Installed: ${CURRENT:-unknown}  →  Latest: ${LATEST}"
[[ "$CURRENT" == "$LATEST" ]] && { log "Already up to date."; exit 0; }

# ── Download ──────────────────────────────────────────────────────────────────

ASSET="Fulcrum-${LATEST}-x86_64-linux.tar.gz"
SHA_ASSET="Fulcrum-${LATEST}-shasums.txt"
DOWNLOAD_URL=$(echo "$RELEASE" | grep "browser_download_url.*${ASSET}\"" | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')
SHA_URL=$(echo "$RELEASE" | grep "browser_download_url.*${SHA_ASSET}\"" | head -1 | sed 's/.*"\(https[^"]*\)".*/\1/')

[[ -n "$DOWNLOAD_URL" ]] || err "Could not find download URL for ${ASSET}."
[[ -n "$SHA_URL"      ]] || err "Could not find SHA file URL."

log "Downloading ${ASSET} ..."
curl -fsSL --progress-bar -o "$TMP/${ASSET}"     "$DOWNLOAD_URL"
curl -fsSL -o "$TMP/${SHA_ASSET}" "$SHA_URL"

# ── SHA256 verification ───────────────────────────────────────────────────────

log "Verifying SHA256 checksum ..."
(cd "$TMP" && grep "$ASSET" "$SHA_ASSET" | sha256sum -c --strict) \
  || err "SHA256 checksum mismatch."

# ── Install ───────────────────────────────────────────────────────────────────

log "Extracting and installing binary ..."
tar -xzf "$TMP/${ASSET}" -C "$TMP"
BINARY=$(find "$TMP" -name "Fulcrum" -type f | head -1)
[[ -n "$BINARY" ]] || err "Fulcrum binary not found in archive."
install -m 0755 "$BINARY" "$INSTALL_DIR/fulcrum"

log "Restarting fulcrum ..."
systemctl restart fulcrum

log "Fulcrum ${LATEST} installed successfully."
