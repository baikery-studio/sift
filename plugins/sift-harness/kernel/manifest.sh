#!/usr/bin/env bash
# kernel/manifest.sh — per-run provenance manifest. Pins base_sha / feature_sha /
# extended_hash / scope for a packet run under .harness/runs/<id>/<run>.json, so
# W1 and witness-binding can verify a verdict against a fixed, recorded run.
_MAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_MAN_DIR/config.sh"
SIFT_STATE="${SIFT_STATE:-$(config_path state)}"

# manifest_write PACKET_ID [EXTENDED_HASH]  -> prints the manifest path
manifest_write() {
  id="$1"; ehash="${2:-}"
  root="${SIFT_REPO_ROOT:-$(pwd)}"
  fsha="$(git -C "$root" rev-parse --verify --quiet HEAD 2>/dev/null || echo nogit)"
  bsha="$(git -C "$root" rev-parse --verify --quiet HEAD~1 2>/dev/null || echo "$fsha")"
  d="$SIFT_STATE/runs/$id"; mkdir -p "$d"
  rid="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  python3 -c 'import json,sys
print(json.dumps({"schema":"manifest/v1","packet_id":sys.argv[1],"base_sha":sys.argv[2],"feature_sha":sys.argv[3],"extended_hash":sys.argv[4],"run_id":sys.argv[5]}))' \
    "$id" "$bsha" "$fsha" "$ehash" "$rid" > "$d/$rid.json"
  printf '%s\n' "$d/$rid.json"
}
