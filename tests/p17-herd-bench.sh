#!/usr/bin/env bash
# Acceptance for PRV-1-HERD-BENCH. RED before (no engage_gate measure), GREEN after.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'engage_gate' "$ROOT/benchmarks/bench.sh" || fail "bench.sh has no engage-gate measure (RED)"

o="$(mktemp -d)"; trap 'rm -rf "$o"' EXIT
BENCH_OUT_DIR="$o" BENCH_TRIALS=4 BENCH_TASKS=4 BENCH_ENGAGE_TRIALS=5 bash "$ROOT/benchmarks/bench.sh" >/dev/null 2>&1 || fail "bench run failed"
[ -f "$o/results.json" ] || fail "no results.json"
python3 - "$o/results.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); eg=d.get("engage_gate") or {}
assert eg, "results.json has no engage_gate block"
assert eg["escape_gate_off"] > eg["escape_gate_on"], "gate OFF must escape more than ON"
assert eg["escape_gate_on"] == 0, "gate ON must block all freehand bails (escape 0)"
PY
grep -qi 'engage-gate' "$o/report.md" || fail "report.md has no engage-gate section"

# reproducible: a second run gives the same engage_gate numbers
o2="$(mktemp -d)"; BENCH_OUT_DIR="$o2" BENCH_TRIALS=4 BENCH_TASKS=4 BENCH_ENGAGE_TRIALS=5 bash "$ROOT/benchmarks/bench.sh" >/dev/null 2>&1 || fail "second bench failed"
a="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["engage_gate"]["escape_rate_off"],json.load(open(sys.argv[1]))["engage_gate"]["escape_rate_on"])' "$o/results.json")"
b="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["engage_gate"]["escape_rate_off"],json.load(open(sys.argv[1]))["engage_gate"]["escape_rate_on"])' "$o2/results.json")"
rm -rf "$o2"
[ "$a" = "$b" ] || fail "engage-gate not reproducible ($a vs $b)"
echo "PASS: bench measures engage-gate (OFF escapes, ON blocks all), reproducible, report.md updated"
