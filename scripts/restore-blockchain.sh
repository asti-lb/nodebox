#!/usr/bin/env bash
set -euo pipefail

# NodeBox — Restore blockchain from sda backup
# Mounts /dev/sda1 and rsyncs blocks/chainstate/indexes to /data/bitcoin/
# Usage: sudo bash restore-blockchain.sh

log()  { echo "[+] $*"; }
err()  { echo "[!] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"

BACKUP_DEV="/dev/sda1"
BACKUP_MNT="/mnt/sda-backup"
DATA_DIR="/data/bitcoin"

# Verify backup device exists
[[ -b "$BACKUP_DEV" ]] || err "Backup device $BACKUP_DEV not found. Is the drive connected?"

# Verify destination exists and is owned by bitcoin
[[ -d "$DATA_DIR" ]] || err "$DATA_DIR does not exist. Run setup-base.sh first."

log "Mounting $BACKUP_DEV ..."
mkdir -p "$BACKUP_MNT"
mount "$BACKUP_DEV" "$BACKUP_MNT"

BACKUP_BITCOIN="$BACKUP_MNT/bitcoin"
[[ -d "$BACKUP_BITCOIN" ]] || { umount "$BACKUP_MNT"; err "No bitcoin/ directory found on $BACKUP_DEV"; }

log "Restoring blockchain data (~876 GB, approx. 30 min) ..."
rsync -a --info=progress2 \
    "$BACKUP_BITCOIN/blocks"     "$DATA_DIR/" \
    --exclude='*.lock'

rsync -a --info=progress2 \
    "$BACKUP_BITCOIN/chainstate" "$DATA_DIR/"

rsync -a --info=progress2 \
    "$BACKUP_BITCOIN/indexes"    "$DATA_DIR/"

log "Setting ownership ..."
chown -R bitcoin:bitcoin "$DATA_DIR"

log "Unmounting backup drive ..."
umount "$BACKUP_MNT"

log "Blockchain restore complete."
log "Next: run scripts/install-bitcoin-core.sh <version>"
