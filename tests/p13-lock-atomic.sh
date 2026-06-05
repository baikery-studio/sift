#!/usr/bin/env bash
# Acceptance for HD2-2-LOCK-ATOMIC. RED before (rm-then-mkdir reclaim), GREEN after (mv-steal).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }

# structural: the naive rm-rf-then-mkdir reclaim is gone; an atomic mv-steal is present
if grep -qE 'rm -rf "\$SIFT_STATE/dispatch\.lock\.d"' "$ROOT/kernel/lock.sh" \
   && ! grep -q 'mv ' "$ROOT/kernel/lock.sh"; then
  fail "lock.sh still uses rm-then-mkdir reclaim with no mv-steal (RED)"
fi
grep -q 'mv ' "$ROOT/kernel/lock.sh" || fail "lock.sh has no atomic mv-steal"

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
export SIFT_REPO_ROOT="$w" SIFT_STATE="$w/.harness"
mkdir -p "$SIFT_STATE"
. "$ROOT/kernel/lock.sh"

# 1. a STALE lock (dead PID) is reclaimed
mkdir -p "$SIFT_STATE/dispatch.lock.d"; printf '999999\n' > "$SIFT_STATE/dispatch.lock.d/pid"
sift_lock_acquire alpha || fail "did not reclaim a stale (dead-PID) lock"
[ "$(cat "$SIFT_STATE/dispatch.lock.d/pid")" = "$$" ] || fail "reclaimed lock does not hold our PID"
[ "$(cat "$SIFT_STATE/active")" = "alpha" ] || fail "active marker not set on reclaim"

# 2. a LIVE lock is NOT stolen by a second acquirer (run in a subshell = different attempt)
( . "$ROOT/kernel/lock.sh"; SIFT_STATE="$w/.harness"; sift_lock_acquire beta ) && fail "stole a LIVE lock (double ownership)"
[ "$(cat "$SIFT_STATE/active")" = "alpha" ] || fail "live lock owner changed under a failed steal"

# 3. release clears it, then it can be acquired again
sift_lock_release
[ -d "$SIFT_STATE/dispatch.lock.d" ] && fail "release did not remove the lock dir"
sift_lock_acquire gamma || fail "could not acquire after release"

echo "PASS: stale lock reclaimed atomically (mv-steal), live lock not stolen, release works"
