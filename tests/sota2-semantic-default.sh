#!/usr/bin/env bash
# tests/sota2-semantic-default.sh — durable suite mirror for SOTA-2-SEMANTIC-DEFAULT. Under
# the EXPLICIT agent-host signal SIFT_AGENT_HOST=1, the default W3 requires a host-written
# R1-R13 verdict (landed via the sanctioned `sift w3-verdict` verb, validated by the
# W3-SEM-1 rubric-VALUE check); ambient CLAUDE_PROJECT_DIR alone stays keyless (so CI is not
# silently flipped); offline/CI stays keyless (selftest unchanged); explicit opt-out works;
# zero egress is preserved. Delegates to the packet's acceptance snapshot so the suite and the
# witness check the same contract.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/SOTA-2-SEMANTIC-DEFAULT/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
