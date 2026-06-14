#!/usr/bin/env bash
# tests/tamper-review-1.sh — durable suite mirror for TAMPER-REVIEW-1. The anti-test-tampering
# signature scan re-runs at REVIEW time over the packet's whole committed changed set (base..HEAD),
# so a weakened sibling test introduced after execute cannot ride to a clean confirmed; and
# kernel/_signatures.py recognises a '.sh' test file. Delegates to the packet's acceptance
# snapshot so the suite and the witness check the same contract.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/TAMPER-REVIEW-1/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
