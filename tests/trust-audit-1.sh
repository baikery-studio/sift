#!/usr/bin/env bash
# tests/trust-audit-1.sh — durable suite mirror for TRUST-AUDIT-1. The audit verifier
# (kernel/_audit.py) must be self-sufficient: invoked directly it fails a tampered chain and
# a forged witness-binding on its own (not relying on audit.sh having gated first), and a
# genuine witness-bound partially_confirmed must be auditable. Delegates to the packet's
# acceptance snapshot so the suite and the witness check the same contract.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/TRUST-AUDIT-1/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
