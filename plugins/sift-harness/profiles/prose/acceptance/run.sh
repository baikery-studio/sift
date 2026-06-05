#!/usr/bin/env bash
# Prose profile acceptance runner (PROFILE_INTERFACE §3.1):
#   acceptance_run(packet_path, packet_id) -> { passed, evidence, conformance }
#
# The acceptance bar is the "reproduce" analog for a writing task: the declared
# deliverable EXISTS and is NON-EMPTY. The semantic completeness check (all declared
# sections present) is the W4 witness's job, so a non-empty-but-incomplete deliverable
# passes acceptance and is then rejected by W4 — demonstrating the witness slot carries
# the goal-addressing teeth. No software concept (test command, require_red_first) here.
set -euo pipefail
ACC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# reuse the prose W4's stdlib frontmatter reader + path containment
source "$ACC_HERE/../witness_w4.sh"

acceptance_run() {
  local packet_path="${1:-}"
  if [ -z "$packet_path" ] || [ ! -f "$packet_path" ]; then
    printf '{ "passed": false, "evidence": { "error": "packet not found" }, "conformance": null }\n'; return 1
  fi
  local artifact
  artifact="$(prose_fm "$packet_path" artifact.path)" \
    || { printf '{ "passed": false, "evidence": { "error": "frontmatter parse failed" }, "conformance": null }\n'; return 1; }
  prose_path_contained "$artifact" \
    || { printf '{ "passed": false, "evidence": { "error": "artifact.path escapes repo root (traversal rejected)" }, "conformance": null }\n'; return 1; }
  local apath="$artifact"
  case "$apath" in /*) ;; *) apath="${SIFT_REPO_ROOT:-$(pwd)}/$apath" ;; esac
  local jart; jart="$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$artifact")"
  if [ -s "$apath" ]; then
    printf '{ "passed": true, "evidence": { "artifact": %s, "exists": true, "nonempty": true }, "conformance": null }\n' "$jart"; return 0
  fi
  printf '{ "passed": false, "evidence": { "artifact": %s, "exists": false }, "conformance": null }\n' "$jart"; return 1
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then acceptance_run "$@"; fi
