#!/usr/bin/env bash
# tests/w4-caller-1.sh — durable suite mirror for W4-CALLER-1. The W4 wiring witness proves
# REACHABILITY against git-TRACKED files, not mere textual presence: two non-test tracked files
# that only DEFINE the symbol (no caller) FAIL, the sole caller in an UNTRACKED file does not
# count, a test-only reference does not count, and a def + a real tracked non-test caller still
# PASSES. Delegates to the packet's acceptance snapshot so the suite and the witness agree.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/W4-CALLER-1/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
