#!/usr/bin/env bash
# selftest: SECURITY.md exists, discloses (not overclaims), and README links it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/SECURITY.md" ] || { echo "SECURITY.md absent"; exit 1; }
for t in 'tamper.?evident' 'advisory' 'keyless|zero.?egress' 'unsandboxed' 'no network|makes no network|nothing.*leaves|no.*egress'; do
  grep -iqE "$t" "$ROOT/SECURITY.md" || { echo "SECURITY.md missing disclosure: $t"; exit 1; }
done
if grep -iqE 'tamper.?proof|sandboxed by default|guarantee[ds]? (no|zero) (data|egress)' "$ROOT/SECURITY.md"; then
  echo "SECURITY.md overclaims"; exit 1
fi
grep -iqE 'SECURITY\.md|security (&|and) data egress|security policy' "$ROOT/README.md" \
  || { echo "README does not link SECURITY.md"; exit 1; }
echo "PASS: SECURITY.md discloses (no overclaim) + README links it"
