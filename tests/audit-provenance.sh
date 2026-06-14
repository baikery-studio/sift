#!/usr/bin/env bash
# tests/audit-provenance.sh — durable suite mirror for AUDIT-PROVENANCE. `sift audit` surfaces
# the W2 reproduce mode from <id>.w2.json and labels a confirmed PASS(degraded) when the mode is
# fresh_clone_unavailable or feature_sha is unresolved (nogit), instead of an indistinguishable
# clean PASS; a clean_checkout confirmed stays a plain PASS. Delegates to the acceptance snapshot.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/AUDIT-PROVENANCE/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
