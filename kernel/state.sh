#!/usr/bin/env bash
# kernel/state.sh — state by causally-validated replay over the hash-chained log.
_STATESH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_STATESH_DIR/config.sh"
SIFT_LOG="${SIFT_LOG:-$(config_path log)}"
SIFT_REVIEWS="${SIFT_REVIEWS:-$(config_path reviews)}"

# project_state PACKET_ID  → submitted|packeted|...|confirmed|corrupt
project_state() {
  python3 "$_STATESH_DIR/_state.py" "$SIFT_LOG" "$1" "$SIFT_REVIEWS"
}

# sift_abort <id> — in-band recovery for a packet wedged after a crash (e.g. stuck in
# reviewing). Emits a LEGAL chained transition to a re-runnable state and clears focus,
# so recovery never needs hand-editing the log. reviewing->review_failed, executing->failed.
sift_abort() {
  . "$_STATESH_DIR/log.sh"
  local id="${1:-}"; [ -n "$id" ] || { echo "[sift] usage: sift abort <id>" >&2; return 1; }
  local st; st="$(project_state "$id")"
  local sd="${SIFT_STATE:-$(config_path state)}"
  case "$st" in
    reviewing) log_append lane.transition reviewing review_failed "$id" >/dev/null
               rm -f "$sd/focus" 2>/dev/null || true
               echo "[sift] aborted $id (reviewing -> review_failed); fix and re-execute" ;;
    executing) log_append lane.transition executing failed "$id" >/dev/null
               rm -f "$sd/focus" 2>/dev/null || true
               echo "[sift] aborted $id (executing -> failed); re-execute to retry" ;;
    *) echo "[sift] $id not in an abortable state (is '$st')" >&2; return 1 ;;
  esac
}
