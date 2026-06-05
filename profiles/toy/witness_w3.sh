#!/usr/bin/env bash
# Toy profile W3 — DETERMINISTIC, KEYLESS (no LLM / no API call).
#
# This is the keyless deterministic-only review mode: a
# well-formed toy packet passes, and it writes the FRESH W3 verdict artifact that
# the kernel hashes into the terminal `confirmed` event (witness-binding). The
# SOFTWARE profile's W3 is the LLM reviewer (reviewer-prompt overlay); the toy
# keeps W3 keyless so the spine proves end-to-end with zero API cost. No software
# concept appears here — same witness slot, a different (trivial) job.
set -euo pipefail
W3_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./witness_w4.sh
source "$W3_HERE/witness_w4.sh"   # reuse the stdlib frontmatter reader; not auto-invoked

witness_w3() {
  # witness_w3 <packet_path> <packet_id>
  local packet_path="${1:-}" packet_id="${2:-}"
  local reviews_dir="${SIFT_REVIEWS:-.harness/reviews}"
  mkdir -p "$reviews_dir"
  local goal art marker
  goal="$(toy_w4_fm_get "$packet_path" goal 2>/dev/null || true)"
  art="$(toy_w4_fm_get "$packet_path" artifact.path 2>/dev/null || true)"
  marker="$(toy_w4_fm_get "$packet_path" artifact.marker 2>/dev/null || true)"
  if [ -z "$goal" ] || [ -z "$art" ] || [ -z "$marker" ]; then
    printf '{ "ok": false, "verdict": "reject", "reason": "malformed toy packet (missing goal/artifact/marker)" }\n'
    return 1
  fi
  printf '{ "verdict": "pass", "profile": "toy", "mode": "deterministic-keyless", "reason": "well-formed toy packet; goal+artifact+marker present" }\n' \
    > "$reviews_dir/$packet_id.w3.json"
  printf '{ "ok": true, "verdict": "pass", "w3_mode": "deterministic-keyless" }\n'
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then witness_w3 "$@"; fi
