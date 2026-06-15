#!/usr/bin/env bash
# tests/orch-4-decision-trace.sh — durable suite mirror for ORCH-4-DECISION-TRACE. Orchestrator
# decisions (orch.* / packet.emit on a reserved __wave__:<wid> scope, actor=orchestrator) ride
# the tamper-evident chain INERT to state projection (the above-core boundary), and `sift trace
# <wid>` surfaces a wave's decisions filtered to that wave. Delegates to the acceptance snapshot.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/ORCH-4-DECISION-TRACE/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
