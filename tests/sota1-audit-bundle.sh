#!/usr/bin/env bash
# tests/sota1-audit-bundle.sh — durable suite mirror for SOTA-1-AUDIT-BUNDLE. `sift export <id>`
# writes ONE portable bundle carrying a witness-bound terminal; `sift audit --bundle <file>`
# replay-verifies it on a foreign machine with no .harness present (chain -> project_state ->
# artifact re-hash), fails an in-content log-line flip AND an artifact byte-swap, and surfaces
# the bundle's feature_sha cross-repo provenance (NOT-FOUND in a foreign repo, PRESENT when the
# commit is in the audit repo). Delegates to the packet's acceptance snapshot.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/SOTA-1-AUDIT-BUNDLE/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
