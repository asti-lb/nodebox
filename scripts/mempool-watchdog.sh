#!/usr/bin/env bash
#
# mempool-watchdog.sh — detect a stalled mempool.space block indexer and heal it.
#
# The mempool backend can keep running (serving the API, ingesting unconfirmed
# transactions) while its block-indexing loop silently dies. systemd sees the
# process as healthy, so "Restart=on-failure" never fires. This watchdog compares
# mempool's indexed tip against Bitcoin Core's tip and restarts the service when
# the tip has stopped advancing while falling behind.
#
# Run periodically via mempool-watchdog.timer. Must run as root (systemctl +
# reads Bitcoin Core's cookie). Logs to stdout → journal.
set -euo pipefail

BITCOIN_CLI="/usr/local/bin/bitcoin-cli"
BITCOIN_DATADIR="/data/bitcoin"
MEMPOOL_TIP_URL="http://127.0.0.1:8080/api/v1/blocks/tip/height"
UNIT="mempool-backend"
STATE_FILE="/var/lib/nodebox/mempool-watchdog.state"

# Restart only once mempool trails Core by at least this many blocks AND has not
# advanced for STALL_SECONDS. The two conditions together avoid false positives
# during normal operation and during a legitimate catch-up (where the tip keeps
# climbing, resetting the stall timer every run).
LAG_THRESHOLD=3
STALL_SECONDS=1800   # 30 min without the tip moving while behind

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') mempool-watchdog: $*"; }

core_tip=$("$BITCOIN_CLI" -datadir="$BITCOIN_DATADIR" getblockcount 2>/dev/null || echo "")
mpl_tip=$(curl -s --max-time 5 "$MEMPOOL_TIP_URL" 2>/dev/null || echo "")

# Bail quietly if either side is unreadable (e.g. Core in IBD, mempool starting).
if ! [[ "$core_tip" =~ ^[0-9]+$ ]] || ! [[ "$mpl_tip" =~ ^[0-9]+$ ]]; then
  log "skip: unreadable height (core='$core_tip' mempool='$mpl_tip')"
  exit 0
fi

now=$(date +%s)
lag=$((core_tip - mpl_tip))

# Load previous observation: "<height> <changed_at_epoch>".
prev_height=""
changed_at="$now"
if [[ -r "$STATE_FILE" ]]; then
  read -r prev_height changed_at < "$STATE_FILE" || true
fi

# Reset the stall timer whenever the tip actually moved (or on first run).
if [[ "$mpl_tip" != "$prev_height" ]]; then
  changed_at="$now"
fi

mkdir -p "$(dirname "$STATE_FILE")"
printf '%s %s\n' "$mpl_tip" "$changed_at" > "$STATE_FILE"

stalled_for=$((now - changed_at))

if (( lag >= LAG_THRESHOLD && stalled_for >= STALL_SECONDS )); then
  log "STALL: tip stuck at $mpl_tip for ${stalled_for}s, ${lag} blocks behind Core ($core_tip) — restarting $UNIT"
  systemctl restart "$UNIT"
  # Give the fresh process time before the next evaluation.
  printf '%s %s\n' "$mpl_tip" "$now" > "$STATE_FILE"
  exit 0
fi

if (( lag >= LAG_THRESHOLD )); then
  log "behind by ${lag} blocks (tip $mpl_tip vs $core_tip), unchanged for ${stalled_for}s — within grace, watching"
fi
exit 0
