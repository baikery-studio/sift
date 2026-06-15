#!/usr/bin/env bash
# tests/scale-memo.sh — durable suite mirror for SCALE-MEMO. project_state parses each log line
# once and verifies the hash-chain ONCE per process invocation (an in-process, mtime/size-keyed
# memo, no persisted checkpoint), reusing the verified event list across every per-packet
# projection: doctor/status/wave/drive go O(P×N) -> O(N+P). Trust semantics are byte-identical
# (a tampered log still replays corrupt; doctor still catches a content-tampered artifact; the
# per-packet witness re-hash is never skipped). Delegates to the acceptance snapshot.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/SCALE-MEMO/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
