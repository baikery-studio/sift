#!/usr/bin/env bash
# tests/engage-cold-1.sh — durable suite mirror for ENGAGE-COLD-1. The cold-repo engage gate:
# a freehand edit in a repo with no .harness/ and no config arms a `cold-engage` marker, and
# the Stop hook blocks on it (offering `sift setup`); a cold repo with NO edit still ends
# freely; running `sift setup` clears the gate. Delegates to the packet's acceptance snapshot
# so the suite and the witness check the same contract.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/ENGAGE-COLD-1/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
