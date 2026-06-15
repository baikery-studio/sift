#!/usr/bin/env bash
# tests/orch-2-gap-replan.sh — durable suite mirror for ORCH-2-GAP-REPLAN. The drive loop's
# coverage-fed replan step turns an UNCOVERED goal_requirement into an append-only action:
# scaffold a covering packet (seeded to cover the requirement), append it to the wave manifest
# members[], and log a CHAINED packet.emit (inert to state projection); an all-covered wave is a
# no-op; coverage stays advisory; the chain still verifies. Delegates to the acceptance snapshot.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/ORCH-2-GAP-REPLAN/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
