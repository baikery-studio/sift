#!/usr/bin/env bash
# Toy profile acceptance runner.
#
# Implements the kernel contract (PROFILE_INTERFACE §3.1):
#   acceptance_run(packet_path, packet_id, sandbox_ctx)
#     -> { passed, evidence, conformance }
#
# The toy bar is the simplest possible NON-software acceptance: the declared
# artifact file exists and contains the declared marker substring. There is no
# test command, no pinned analysis plan, so conformance is null (mirroring the
# software profile's null, for a totally different reason: there is simply no
# plan to conform to here).
#
# Reads ONLY toy-profile frontmatter (goal, artifact.path, artifact.marker).
# Uses NO software-profile concept (acceptance_tests[].script, command,
# require_red_first wiring). Fail-closed on parse/IO error.
set -euo pipefail

ACC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Reuse the toy W4's stdlib-only frontmatter reader.
# shellcheck source=../witness_w4.sh
source "$ACC_HERE/../witness_w4.sh"

acceptance_run() {
  # acceptance_run <packet_path> <packet_id> [<sandbox_ctx>]
  local packet_path="${1:-}"
  if [ -z "$packet_path" ] || [ ! -f "$packet_path" ]; then
    printf '{ "passed": false, "evidence": { "error": "packet not found" }, "conformance": null }\n'
    return 1
  fi
  local artifact marker
  artifact="$(toy_w4_fm_get "$packet_path" artifact.path)" || {
    printf '{ "passed": false, "evidence": { "error": "frontmatter parse failed" }, "conformance": null }\n'; return 1; }
  marker="$(toy_w4_fm_get "$packet_path" artifact.marker)" || {
    printf '{ "passed": false, "evidence": { "error": "frontmatter parse failed" }, "conformance": null }\n'; return 1; }
  toy_path_contained "$artifact" || {
    printf '{ "passed": false, "evidence": { "error": "artifact.path escapes repo root (traversal rejected)" }, "conformance": null }\n'; return 1; }

  # resolve the artifact against SIFT_REPO_ROOT, not the caller's cwd
  local apath="$artifact"
  case "$apath" in /*) ;; *) apath="${SIFT_REPO_ROOT:-$(pwd)}/$apath" ;; esac
  local jart; jart="$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$artifact")"  # JSON-safe

  local exists=false has_marker=false
  [ -f "$apath" ] && exists=true
  if [ "$exists" = true ] && grep -qF -- "$marker" "$apath"; then
    has_marker=true
  fi

  if [ "$exists" = true ] && [ "$has_marker" = true ]; then
    printf '{ "passed": true, "evidence": { "artifact": %s, "exists": true, "marker_present": true }, "conformance": null }\n' "$jart"
    return 0
  fi
  printf '{ "passed": false, "evidence": { "artifact": %s, "exists": %s, "marker_present": %s }, "conformance": null }\n' \
    "$jart" "$exists" "$has_marker"
  return 1
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  acceptance_run "$@"
fi
