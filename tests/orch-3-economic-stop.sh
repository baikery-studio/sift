#!/usr/bin/env bash
# tests/orch-3-economic-stop.sh — durable suite mirror for ORCH-3-ECONOMIC-STOP. The drive loop's
# economic-stop governor counts a packet's failed transitions (executing->failed +
# reviewing->review_failed) from the VERIFIED chain and, at >= max_retries, emits a chained
# orch.decision{halt,retry_ceiling} and stops driving it; below the ceiling it does not halt; it
# refuses to halt/supersede an already-confirmed packet; the decision is INERT to state projection
# (project_state unchanged, chain verifies, _state.py consumes no orch.* kind); zero egress.
# Delegates to the packet's acceptance snapshot.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/ORCH-3-ECONOMIC-STOP/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
