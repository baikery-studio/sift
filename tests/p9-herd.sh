#!/usr/bin/env bash
# tests/p9-herd.sh — selftest gate for the HERD live-steering hooks (HERD-1/2/3).
# Locks the runtime behavior (not just the wiring p2 checks) into `sift selftest`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
export SIFT_REPO_ROOT="$w"
"$SIFT" setup >/dev/null 2>&1 || fail "setup failed"
"$SIFT" packet new p9 --profile toy >/dev/null 2>&1 || fail "packet new failed"
"$SIFT" plan p9 >/dev/null 2>&1 || fail "plan failed"

stop(){ printf '{}' | SIFT_REPO_ROOT="$w" bash "$ROOT/hooks/stop-block.sh" 2>/dev/null || true; }
reinject(){ printf '{}' | SIFT_REPO_ROOT="$w" bash "$ROOT/hooks/userprompt-reinject.sh" 2>/dev/null || true; }
posttool(){ printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" | SIFT_REPO_ROOT="$w" bash "$ROOT/hooks/posttool-reset.sh" 2>/dev/null || true; }

# Stop blocks while planned-but-not-confirmed
stop | grep -q '"block"' || fail "stop-block did not block an in-flight packet"
# UserPromptSubmit injects the active-focus contract
reinject | grep -q 'p9' || fail "reinject did not name the active packet"

# Reach acceptance_met, then an in-scope edit must flag stale acceptance
mkdir -p "$w/out" && printf 'a scaffolded greeting\np9-OK\n' > "$w/out/p9.txt"
"$SIFT" execute p9 >/dev/null 2>&1 || fail "execute failed"
[ "$("$SIFT" state p9 2>/dev/null)" = acceptance_met ] || fail "expected acceptance_met"
posttool "$w/out/p9.txt" | grep -qi 'stale\|re-run' || fail "posttool-reset did not flag stale acceptance"
ls "$w/.harness/"dirty.p9 >/dev/null 2>&1 || fail "no dirty marker after in-scope post-acceptance edit"

# Drive to confirmed → stop allows, reinject silent
"$SIFT" review p9 >/dev/null 2>&1 || fail "review failed"
[ "$("$SIFT" state p9 2>/dev/null)" = confirmed ] || fail "p9 not confirmed"
stop | grep -q '"block"' && fail "stop-block blocked after confirmed"
[ -z "$(reinject)" ] || fail "reinject not silent after confirmed (focus cleared)"

echo "ok"
