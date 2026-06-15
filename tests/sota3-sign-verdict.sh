#!/usr/bin/env bash
# tests/sota3-sign-verdict.sh — durable suite mirror for SOTA-3-SIGN-VERDICT. Opt-in
# `sift review --sign` signs the canonical verdict event_hash with a LOCAL ssh key (zero
# network), records the signer PUBLIC key in the chained review.verdict event, and `sift audit`
# reports signed-attested; a corrupted .sig fails audit; --sign with no key fails closed; an
# unsigned confirmed still audits PASS (keyless default); test-no-egress stays green. Delegates
# to the packet's acceptance snapshot (which drives the real plan->execute->review->audit loop).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SNAP="$DIR/../evals/snapshots/SOTA-3-SIGN-VERDICT/test.sh"
[ -f "$SNAP" ] || { echo "FAIL: missing snapshot $SNAP" >&2; exit 1; }
bash "$SNAP"
