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
