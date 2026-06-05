#!/usr/bin/env bash
# tests/p12-weak-acceptance.sh — selftest gate for FORT-4: doctor flags an unwritten-stub
# acceptance and the scaffolder warns about it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
export SIFT_REPO_ROOT="$w"
"$SIFT" setup >/dev/null 2>&1 || fail "setup failed"
out="$("$SIFT" packet new wk --profile toy 2>&1)"
printf '%s' "$out" | grep -qiE 'weak|placeholder' || fail "scaffolder did not warn"
dout="$("$SIFT" doctor 2>&1 || true)"
printf '%s' "$dout" | grep -qi 'weak acceptance' || fail "doctor did not flag the unwritten stub"
echo "ok"
