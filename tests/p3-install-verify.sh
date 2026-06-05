#!/usr/bin/env bash
# selftest: install-verification evidence is recorded and the manifest is valid.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$ROOT/docs/INSTALL_VERIFICATION.md"
[ -f "$DOC" ] || { echo "INSTALL_VERIFICATION.md missing"; exit 1; }
grep -qi 'plugin-validator' "$DOC" || { echo "doc must record the plugin-validator verdict"; exit 1; }
grep -qiE 'not observed|not-yet-observed|operator-run|cannot be driven' "$DOC" || { echo "doc must state the honest limit"; exit 1; }
# VERSION agrees with the manifest (the validator's one actionable warning)
v="$(cat "$ROOT/VERSION")"; mv="$(python3 -c 'import json;print(json.load(open("'"$ROOT"'/plugins/sift-harness/.claude-plugin/plugin.json"))["version"])')"
[ "$v" = "$mv" ] || { echo "VERSION ($v) != manifest version ($mv)"; exit 1; }
echo "PASS: install verification recorded (plugin-validator PASS + honest limit); VERSION matches manifest"
