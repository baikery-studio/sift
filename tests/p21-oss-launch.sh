#!/usr/bin/env bash
# Acceptance for OSS-LAUNCH-1. RED before (no governance/demo/version-bump), GREEN after.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }

for f in CONTRIBUTING.md CODE_OF_CONDUCT.md CHANGELOG.md \
         .github/ISSUE_TEMPLATE/bug_report.md .github/ISSUE_TEMPLATE/feature_request.md \
         .github/PULL_REQUEST_TEMPLATE.md scripts/demo.sh; do
  [ -s "$ROOT/$f" ] || fail "missing/empty: $f"
done

# version lockstep VERSION == bundle plugin.json == marketplace plugin entry, and == 0.3.0
v="$(cat "$ROOT/VERSION")"; [ "$v" = "0.3.0" ] || fail "VERSION is $v, expected 0.3.0"
python3 - "$ROOT" "$v" <<'PY'
import json,sys
root,v=sys.argv[1],sys.argv[2]
pj=json.load(open(root+"/plugins/sift-harness/.claude-plugin/plugin.json"))["version"]
me=json.load(open(root+"/.claude-plugin/marketplace.json"))["plugins"][0].get("version")
assert pj==v, "plugin.json version %s != VERSION %s"%(pj,v)
assert me==v, "marketplace plugin entry version %s != VERSION %s"%(me,v)
PY

grep -q '0.3.0' "$ROOT/CHANGELOG.md" || fail "CHANGELOG does not document 0.3.0"
grep -q 'scripts/demo.sh' "$ROOT/README.md" || fail "README does not link the demo"

# the demo actually runs and demonstrates the core claim
out="$(bash "$ROOT/scripts/demo.sh" 2>&1)" || fail "demo.sh errored"
printf '%s' "$out" | grep -q 'hello -> confirmed' || fail "demo did not reach confirmed"
printf '%s' "$out" | grep -q 'forged -> corrupt' || fail "demo did not show forged->corrupt"

# README doc-guards still green
for c in setup state wave-review focus next doctor packet; do grep -qF "$c" "$ROOT/README.md" || fail "README dropped command substring: $c"; done
grep -qE 'SECURITY\.md' "$ROOT/README.md" || fail "README dropped the SECURITY.md link"
echo "PASS: governance files + v0.3.0 lockstep + CHANGELOG + runnable demo (confirmed + forged->corrupt) + README guards green"
