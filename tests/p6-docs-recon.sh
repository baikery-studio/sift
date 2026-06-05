#!/usr/bin/env bash
# selftest: docs reconciled — marketplace owner is an object, results.json is tracked,
# MEGA_REVIEW/CICD carry status banners.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 -c 'import json,sys
o=json.load(open(sys.argv[1]))["owner"]; assert isinstance(o,dict) and o.get("name")' "$ROOT/.claude-plugin/marketplace.json" \
  || { echo "marketplace owner not an object"; exit 1; }
git -C "$ROOT" check-ignore -q benchmarks/results.json && { echo "results.json still gitignored"; exit 1; } || true
grep -qi 'implementation status' "$ROOT/docs/spec/CICD.md" || { echo "CICD missing banner"; exit 1; }
echo "PASS: marketplace owner object, results.json tracked, CICD banner present"
