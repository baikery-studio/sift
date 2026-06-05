#!/usr/bin/env bash
# Acceptance for ADO-3-CLAUDEMD-INIT. RED before (no init-claudemd verb), GREEN after.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'init-claudemd)' "$ROOT/bin/sift" || fail "bin/sift has no init-claudemd verb (RED)"

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
export SIFT_REPO_ROOT="$w"
# 1. no CLAUDE.md → creates it with the standing rule + the confirmed gate
SIFT_REPO_ROOT="$w" "$SIFT" init-claudemd >/dev/null 2>&1 || fail "init-claudemd failed"
[ -f "$w/CLAUDE.md" ] || fail "CLAUDE.md not created"
grep -q 'sift-harness:standing-rule' "$w/CLAUDE.md" || fail "no standing-rule sentinel"
grep -qi 'confirmed' "$w/CLAUDE.md" || fail "standing rule omits the confirmed gate"

# 2. idempotent: a second run does not duplicate the block
SIFT_REPO_ROOT="$w" "$SIFT" init-claudemd >/dev/null 2>&1 || fail "second init-claudemd failed"
n="$(grep -c 'sift-harness:standing-rule (managed' "$w/CLAUDE.md")"
[ "$n" -eq 1 ] || fail "duplicate standing-rule block on re-run (count=$n)"

# 3. appends to an EXISTING CLAUDE.md (preserves prior content)
w2="$(mktemp -d)"; printf '# My Project\n\nExisting guidance.\n' > "$w2/CLAUDE.md"
SIFT_REPO_ROOT="$w2" "$SIFT" init-claudemd >/dev/null 2>&1 || fail "append failed"
grep -q 'Existing guidance' "$w2/CLAUDE.md" || fail "clobbered existing CLAUDE.md content"
grep -q 'sift-harness:standing-rule' "$w2/CLAUDE.md" || fail "did not append the standing rule"
rm -rf "$w2"
echo "PASS: init-claudemd creates/append the standing rule, idempotent, preserves existing content"
