#!/usr/bin/env bash
# tests/p11-engage-gate.sh — selftest gate for FORT-1: a freehand edit (no packet) arms the
# engage-gate so the Stop hook blocks; plan disarms it; no-edit sessions never block.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
export SIFT_REPO_ROOT="$w"
"$SIFT" setup >/dev/null 2>&1 || fail "setup failed"
stop(){ printf '{}' | SIFT_REPO_ROOT="$w" bash "$ROOT/hooks/stop-block.sh" 2>/dev/null || true; }
post(){ printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" | SIFT_REPO_ROOT="$w" bash "$ROOT/hooks/posttool-reset.sh" 2>/dev/null || true; }

# no-edit session never blocks
stop | grep -q '"block"' && fail "blocked a no-edit session"
# freehand edit arms the gate → block
post "$w/x.txt"
stop | grep -q '"block"' || fail "did not block after a freehand edit"
# plan disarms it
"$SIFT" packet new e1 --profile toy >/dev/null 2>&1; "$SIFT" plan e1 >/dev/null 2>&1
[ -f "$w/.harness/unpacketed-edit" ] && fail "plan did not disarm the engage-gate"

echo "ok"
