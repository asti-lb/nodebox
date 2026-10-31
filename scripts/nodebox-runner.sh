#!/usr/bin/env bash
#
# nodebox-runner.sh — run one task requested by the dashboard, as root.
#
# The dashboard is unprivileged and can only create empty files in $REQUESTS; the
# file name is the task. Running here, outside the dashboard's process tree, lets
# a task outlive the browser, nginx and the dashboard itself.
set -uo pipefail

REQUESTS="/var/lib/nodebox/requests"
LOG="/var/lib/nodebox/task.log"
SCRIPTS="/opt/nodebox/scripts"

shopt -s nullglob
pending=("$REQUESTS"/*)
(( ${#pending[@]} )) || exit 0

# One task at a time: anything else requested meanwhile is dropped.
task=$(basename "${pending[0]}")
rm -rf -- "${pending[@]}"

case "$task" in
  install-public-pool|update-bitcoin-core|update-fulcrum|update-mempool|update-public-pool) ;;
  *) echo "Unknown task: $task" >&2; exit 1 ;;
esac

install -m 0640 -g dashboard /dev/null "$LOG"
echo "[task] $task" >> "$LOG"

if bash "$SCRIPTS/$task.sh" >> "$LOG" 2>&1; then
  echo "[done]" >> "$LOG"
else
  echo "[error] Exit code $?" >> "$LOG"
fi
