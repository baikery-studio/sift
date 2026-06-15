#!/usr/bin/env bash
# tests/w2-worktree.sh — durable suite mirror for W2-WORKTREE. The W2 reproduce witness runs the
# acceptance from a detached git worktree of feature_sha (a true clean checkout), not in-place,
# so an untracked/gitignored feature dependency cannot certify a reproduce; the test oracle is
# copied into the worktree (it verifies the committed feature, it is not feature state); and the
# in-place run remains the explicit fresh_clone_unavailable floor when git/worktree is absent.
# Delegates to the packet's acceptance snapshot so the suite and the witness check the same contract.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/W2-WORKTREE/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
