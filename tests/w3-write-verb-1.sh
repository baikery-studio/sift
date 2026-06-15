#!/usr/bin/env bash
# tests/w3-write-verb-1.sh — durable suite mirror for W3-WRITE-VERB-1. The sanctioned
# `sift w3-verdict <id> <staging>` verb is the ONLY door for an agent-authored host W3 verdict
# to reach .harness/reviews/<id>.w3.json: the scope guard still hard-denies a direct agent
# write there, sift's own code validates the staged verdict and lands it, and a malformed /
# double-verdict staging file is refused without landing any artifact. Delegates to the
# packet's acceptance snapshot so the suite and the witness check the same contract.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/W3-WRITE-VERB-1/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
