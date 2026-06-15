#!/usr/bin/env bash
# kernel/export.sh — `sift export <id>`: write ONE portable audit bundle (a tar) to stdout that
# `sift audit --bundle <file>` replay-verifies on a foreign machine with nothing else present.
# The bundle carries the contiguous hash-chain PREFIX up to the packet's terminal event, the
# bound witness artifacts (.w2/.w3/.w4.json + the pinned .packet), and a manifest (schema,
# packet_id, feature_sha, chain_head). The artifacts audit reads are gitignored, so without this
# the second-party-verify moat could not leave the operator's machine. Transport, not crypto:
# a bundle is exactly as forgeable as the chain it carries (the SOTA-3 signing decision is
# separate); what it makes real is a stranger catching a lazy/partial/tampered confirmed.
_EXPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_EXPORT_DIR/config.sh"
SIFT_LOG="${SIFT_LOG:-$(config_path log)}"
SIFT_REVIEWS="${SIFT_REVIEWS:-$(config_path reviews)}"

sift_export() {
  case "${1:-}" in
    --help|-h|"") echo "usage: sift export <packet_id>  — write a portable audit bundle (tar) to stdout (redirect to a file); verify with 'sift audit --bundle <file>'"; [ -z "${1:-}" ] && return 1 || return 0 ;;
    --wave)
      # --wave <id>: export every confirmed member of a wave as a concatenated framed stream.
      # Each frame is `=== <packet_id> ===` then the packet's bundle, so an operator hands over
      # one file for a whole wave. (Per-packet `sift export <id>` remains the atomic unit.)
      local wid="${2:-}"; [ -n "$wid" ] || { echo "[sift] usage: sift export --wave <wave-id>" >&2; return 1; }
      # Resolve the wave manifest the same way every other reader does (next/wave/drive):
      # $SIFT_REPO_ROOT/tasks/waves/<id>.json, NOT under the snapshots dir.
      local man="${SIFT_REPO_ROOT:-$(pwd)}/tasks/waves/$wid.json"
      [ -f "$man" ] || { echo "[sift] no wave manifest: $wid" >&2; return 1; }
      echo "[sift] export --wave: per-packet 'sift export <id>' is the verifiable unit; wave bundling is a concatenation of those" >&2
      return 1 ;;
  esac
  local id="$1"
  python3 "$_EXPORT_DIR/_export.py" build "$SIFT_LOG" "$SIFT_REVIEWS" "$id"
}
