#!/usr/bin/env bash
# Prose profile W3 — DETERMINISTIC, KEYLESS (no LLM / no API). A well-formed prose
# packet (goal + artifact.path + declared sections) passes and writes the FRESH W3
# verdict artifact the kernel hashes into the witness-bound `confirmed`. Same witness
# slot as software's LLM reviewer, a trivial keyless job — so the seam proves end-to-end
# at zero API cost. No software concept appears here.
set -euo pipefail
W3_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$W3_HERE/witness_w4.sh"   # reuse the stdlib frontmatter readers

witness_w3() {  # witness_w3 <packet_path> <packet_id>
  local packet_path="${1:-}" packet_id="${2:-}"
  local reviews_dir="${SIFT_REVIEWS:-.harness/reviews}"; mkdir -p "$reviews_dir"
  local goal art secs
  goal="$(prose_fm "$packet_path" goal 2>/dev/null || true)"
  art="$(prose_fm "$packet_path" artifact.path 2>/dev/null || true)"
  secs="$(prose_sections "$packet_path" 2>/dev/null || true)"
  if [ -z "$goal" ] || [ -z "$art" ] || [ -z "$secs" ]; then
    printf '{ "ok": false, "verdict": "reject", "reason": "malformed prose packet (missing goal/artifact/sections)" }\n'; return 1
  fi
  printf '{ "verdict": "pass", "profile": "prose", "mode": "deterministic-keyless", "reason": "well-formed prose packet; goal+artifact+sections present" }\n' \
    > "$reviews_dir/$packet_id.w3.json"
  printf '{ "ok": true, "verdict": "pass", "w3_mode": "deterministic-keyless" }\n'
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then witness_w3 "$@"; fi
