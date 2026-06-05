#!/usr/bin/env bash
# kernel/selftest.sh — run the kernel test suite + a coverage orphan-check.
# Coverage rule (criterion 3 / W5-R2): every kernel + profile IMPL file must be
# referenced from the run graph (another kernel/bin/profile/test file). An impl
# file referenced by nothing is a coverage orphan → fail.
_ST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_ST_DIR/config.sh"

sift_selftest() {
  # recursion guard: a test in the suite must never trigger a full nested selftest
  if [ -n "${SIFT_IN_SELFTEST:-}" ]; then echo "  (nested selftest skipped — recursion guard)"; return 0; fi
  export SIFT_IN_SELFTEST=1
  root="${SIFT_PLUGIN_ROOT:-$(cd "$_ST_DIR/.." && pwd)}"
  fails=0; ran=0
  for t in "$root"/tests/*.sh; do
    [ -f "$t" ] || continue
    ran=$((ran+1))
    if bash "$t" >/dev/null 2>&1; then echo "  ok   $(basename "$t")"; else echo "  FAIL $(basename "$t")"; fails=$((fails+1)); fi
  done
  echo "  selftest: $((ran-fails))/$ran suites green"
  # coverage orphan-check (logic in _selftest_cov.py — avoids heredoc-in-$() on bash 3.2)
  orphans="$(python3 "$_ST_DIR/_selftest_cov.py" "$root")"
  if [ -n "$orphans" ]; then
    echo "  COVERAGE ORPHANS (impl file referenced by nothing):"; printf '    %s\n' $orphans; fails=$((fails+1))
  else
    echo "  coverage: no orphan impl files"
  fi
  [ "$fails" -eq 0 ]
}
