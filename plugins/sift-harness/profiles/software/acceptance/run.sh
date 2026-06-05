#!/usr/bin/env bash
# Software profile acceptance runner. Runs the packet's declared `test` command
# from the repo root; passed iff it exits 0. (RED-first: the test is expected to
# fail on base_sha and pass after the change.)
set -euo pipefail
ACC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SIFT_PLUGIN_ROOT:-$ACC_HERE/../../..}/kernel/packet.sh"   # packet_field

acceptance_run() {
  local pp="$1" id="$2"
  local test_cmd; test_cmd="$(packet_field "$id" test)"
  local root="${SIFT_REPO_ROOT:-$(pwd)}"
  if [ -z "$test_cmd" ]; then
    printf '{ "passed": false, "evidence": {"error":"packet has no test field"}, "conformance": null }\n'; return 1
  fi
  local jt; jt="$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$test_cmd")"  # JSON-safe
  if ( cd "$root" && bash "$test_cmd" >/dev/null 2>&1 ); then
    printf '{ "passed": true, "evidence": {"test":%s}, "conformance": null }\n' "$jt"; return 0
  fi
  printf '{ "passed": false, "evidence": {"test":%s}, "conformance": null }\n' "$jt"; return 1
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then acceptance_run "$@"; fi
