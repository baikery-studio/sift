#!/usr/bin/env bash
# tests/w3-sem-1.sh — durable suite mirror for W3-SEM-1. The host-verdict W3 review must have
# semantic teeth: an all-fail rubric (every R1-R13 reads a fail token) under a top-level "pass"
# is REJECTED, injection-resistance (a planted second verdict object) stays intact, a host-mode
# confirmed surfaces an ADDITIVE w3_mode in `sift audit` (without changing REQUIRED_WE, so a
# confirmed lacking it still replays clean), and zero egress is preserved. Delegates to the
# packet's acceptance snapshot so the suite and the witness check the same contract.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/W3-SEM-1/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
