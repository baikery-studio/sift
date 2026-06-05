#!/usr/bin/env bash
# kernel/log.sh — append-only, hash-chained event log (wraps _log.py).
_LOGSH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_LOGSH_DIR/config.sh"
SIFT_LOG="${SIFT_LOG:-$(config_path log)}"

# log_append KIND FROM TO PACKET [WITNESS_JSON]
log_append() {
  SIFT_KIND="$1" SIFT_FROM="$2" SIFT_TO="$3" SIFT_PACKET="$4" \
  SIFT_WITNESS_JSON="${5:-}" SIFT_ACTOR="${SIFT_ACTOR:-harness}" \
  SIFT_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    python3 "$_LOGSH_DIR/_log.py" append "$SIFT_LOG"
}

# verify_log_chain — tamper-evidence gate; non-zero + line number on any break.
verify_log_chain() {
  python3 "$_LOGSH_DIR/_log.py" verify "$SIFT_LOG"
}
