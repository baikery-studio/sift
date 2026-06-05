#!/usr/bin/env bash
# tests/p10-primer.sh — SessionStart standing primer: present in a sift-set-up repo,
# SILENT in a non-sift repo (no noise in unrelated projects).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIFT="$ROOT/bin/sift"
HOOK="$ROOT/hooks/sessionstart.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }

# 1. a non-sift repo (no config, no .harness) → completely silent
bare="$(mktemp -d)"; trap 'rm -rf "$bare"' EXIT
out="$(SIFT_REPO_ROOT="$bare" CLAUDE_PROJECT_DIR="$bare" bash "$HOOK" 2>/dev/null || true)"
[ -z "$out" ] || fail "emitted output in a non-sift repo (should be silent): $out"

# 2. a sift-set-up repo → emits the standing primer naming the loop + the confirmed gate
w="$(mktemp -d)"; trap 'rm -rf "$bare" "$w"' EXIT
export SIFT_REPO_ROOT="$w"
"$SIFT" setup >/dev/null 2>&1 || fail "setup failed"
out="$(SIFT_REPO_ROOT="$w" CLAUDE_PROJECT_DIR="$w" bash "$HOOK" 2>/dev/null || true)"
printf '%s' "$out" | grep -qi 'sift-harness active' || fail "primer not emitted in a sift-set-up repo"
printf '%s' "$out" | grep -qi 'confirmed' || fail "primer omits the confirmed gate"
printf '%s' "$out" | grep -qiE 'sift-workflow|sift-harness:' || fail "primer names no entry point"

echo "ok"
