#!/usr/bin/env bash
# kernel/status.sh — read-only operator status surface. Everything is DERIVED from
# the log + focus marker; this writes nothing (safe to call any time, in any hook).
_ST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_ST_DIR/config.sh"
SIFT_STATE="${SIFT_STATE:-$(config_path state)}"

sift_status() {
  local wid="${1:-phase1}"
  local sift="$_ST_DIR/../bin/sift"
  # truly read-only: project_state never writes (the checkpoint was dropped in HD2-1)
  local focus="none"
  [ -s "$SIFT_STATE/focus" ] && focus="$(tr -d '[:space:]' < "$SIFT_STATE/focus")"
  echo "[sift] status (read-only)"
  echo "  focus packet  : $focus"
  if [ "$focus" != none ] && [ -n "$focus" ]; then
    echo "  focus state   : $("$sift" state "$focus" 2>/dev/null || echo unknown)"
  fi
  echo "  wave '$wid' next : $("$sift" next "$wid" 2>/dev/null || echo UNKNOWN)"
  echo "  log integrity : $("$sift" verify-log 2>/dev/null | tail -1 || echo '(no log)')"
  echo "  doctor        : $("$sift" doctor 2>/dev/null | tail -1 || echo ok)"
  return 0
}
