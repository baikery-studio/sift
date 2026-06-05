#!/usr/bin/env bash
# selftest: the signatures scanner flags test-tampering, passes clean code, and is wired.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIG="$ROOT/kernel/_signatures.py"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
printf 'def test_x():\n    pytest.mark.skip\n    assert True\n' > "$t/a_test.py"
python3 "$SIG" "$t/a_test.py" >/dev/null 2>&1 && { echo "did not flag pytest.mark.skip"; exit 1; }
printf 'def test_ok():\n    assert f() == 1\n' > "$t/b_test.py"
python3 "$SIG" "$t/b_test.py" >/dev/null 2>&1 || { echo "false-positive on clean test"; exit 1; }
printf 'HELP = "see pytest.mark.skip docs"\n' > "$t/notes.py"
python3 "$SIG" "$t/notes.py" >/dev/null 2>&1 || { echo "flagged a string literal in non-test file"; exit 1; }
grep -q '_signatures' "$ROOT/kernel/pipeline.sh" || { echo "gate not wired into pipeline"; exit 1; }
echo "PASS: signatures scanner flags skip, passes clean, low FP on strings, wired into pipeline"
