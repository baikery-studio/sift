#!/usr/bin/env bash
# tests/orch-1-drive-loop.sh — durable suite mirror for ORCH-1-DRIVE-LOOP. `sift drive <wave>`
# is a deterministic loop ABOVE the core: it reads sift_next, dispatches the pipeline step by
# project_state under the dispatch lock held for the whole plan->execute->review iteration
# (WIP=1), repeats until sift_next==ALL-CONFIRMED then runs wave-review; done is derived from the
# log; it never emits lane.transition/review.verdict itself (only the pipeline's witnesses move
# state) and logs choices as orch.decision; it terminates on a missing/non-advancing wave (no
# spin). Delegates to the packet's acceptance snapshot.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/ORCH-1-DRIVE-LOOP/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
