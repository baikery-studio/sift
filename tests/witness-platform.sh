#!/usr/bin/env bash
# tests/witness-platform.sh — durable suite mirror for WITNESS-PLATFORM. The review witness SET
# is data-driven from profile.json: a profile that declares an extra witness (w5, impl writes
# .w5.json) has it INVOKED during review and BOUND in the confirmed event (witness_evidence
# carries w5_hash matching the on-disk artifact), while the default w2/w3/w4 set still confirms
# byte-identically (spine-trustcore + historical confirmeds replay unchanged). Delegates to the
# packet's acceptance snapshot so the suite and the witness check the same contract.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/WITNESS-PLATFORM/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
