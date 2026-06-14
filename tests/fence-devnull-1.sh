#!/usr/bin/env bash
# tests/fence-devnull-1.sh — durable suite mirror for FENCE-DEVNULL-1. The shared Bash
# write-fence parser must treat a no-op `> /dev/null` (and fd-dup / stderr) redirect as
# read-only, keep a genuinely dangling redirect fail-closed, and preserve every
# FENCE-PARSER-1 write-detection and bypass guarantee. Delegates to the packet's acceptance
# snapshot so the suite and the witness check the same contract.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/FENCE-DEVNULL-1/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
