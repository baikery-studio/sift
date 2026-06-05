#!/usr/bin/env bash
# RED-first for SW-2: `sift selftest` exists and its coverage check flags an
# orphan impl. Tests the coverage logic DIRECTLY (via _selftest_cov.py) to avoid
# recursively re-running the whole suite.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/kernel/selftest.sh" ] || { echo "RED: kernel/selftest.sh absent"; exit 1; }
[ -f "$ROOT/kernel/_selftest_cov.py" ] || { echo "RED: _selftest_cov.py absent"; exit 1; }

# 1. clean tree → no orphans
orph="$(python3 "$ROOT/kernel/_selftest_cov.py" "$ROOT")"
[ -z "$orph" ] || { echo "unexpected orphans on clean tree: $orph"; exit 1; }
echo "PASS: coverage clean on the real tree"

# 2. plant an orphan impl (def referenced by nothing) → must be flagged.
#    Use a runtime-unique name so this test's own source does not mention it
#    (else the coverage check would see it "referenced" here).
oname="_orphan_$(date +%s)_$$.sh"
orphan="$ROOT/kernel/$oname"
printf '#!/usr/bin/env bash\n_probe_fn(){ :; }\n' > "$orphan"
orph2="$(python3 "$ROOT/kernel/_selftest_cov.py" "$ROOT")"
rm -f "$orphan"
printf '%s' "$orph2" | grep -q "$oname" || { echo "FAIL: planted orphan ($oname) not flagged"; exit 1; }
echo "PASS: planted coverage orphan is flagged"

# 3. sift selftest is wired into bin/sift
grep -q "sift_selftest" "$ROOT/bin/sift" || { echo "sift_selftest not wired into bin/sift"; exit 1; }
echo "PASS: sift selftest wired"
