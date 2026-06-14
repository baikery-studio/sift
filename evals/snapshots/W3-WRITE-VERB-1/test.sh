#!/usr/bin/env bash
# Acceptance for W3-WRITE-VERB-1. RED on HEAD: there is no 'sift w3-verdict' verb, so the
# host-written R1-R13 review SOTA-2 makes default is UNAUTHORABLE — scope_guard.sh:23-25
# hard-denies any agent write under .harness/, and that is the only place witness_w3 reads
# the host verdict from. Proves: the direct write stays DENIED (the knot is real); the verb
# lands an in-scope agent verdict that host-mode W3 then accepts; a double-verdict staging
# file is refused.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
W3="$ROOT/profiles/software/witness_w3.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS SIFT_W3_REQUIRE_HOST_VERDICT SIFT_W3_HOST_VERDICT 2>/dev/null || true

# ---- 1. the verb must exist -----------------------------------------------------------
grep -qE 'w3-verdict|sift_w3_verdict' "$ROOT/bin/sift" 2>/dev/null \
  || fail "no 'sift w3-verdict' verb (RED until implemented)"

# ---- 2. the knot is real: a DIRECT agent write to the substrate is denied --------------
( . "$ROOT/kernel/scope_guard.sh"
  out="$(scope_guard_decision Write ".harness/reviews/x.w3.json")"; rc=$?
  [ $rc -eq 2 ] || { echo "scope guard did NOT deny a direct .harness write ($out)"; exit 1; }
) || fail "precondition: the scope guard must hard-deny direct .harness/reviews writes (that is why the verb exists)"

# ---- 3. end-to-end: the verb lands an in-scope verdict that host-mode W3 accepts -------
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export SIFT_REPO_ROOT="$T" SIFT_REVIEWS="$T/.harness/reviews"; mkdir -p "$SIFT_REVIEWS"
PK="$T/pkt.md"; printf -- '---\nid: s3\nprofile: software\n---\ngoal: demo\n' > "$PK"
STAGE="$T/staging.w3.json"   # an in-scope path the agent is allowed to write
printf '%s' '{"verdict":"pass","confidence":0.9,"reason":"reviewed","rubric":{"R1":"pass","R2":"pass","R3":"pass","R4":"pass","R5":"pass","R6":"pass","R7":"pass","R8":"pass","R9":"pass","R10":"pass","R11":"pass","R12":"pass","R13":"pass"},"reviewer":"host"}' > "$STAGE"

SIFT_REPO_ROOT="$T" SIFT_REVIEWS="$SIFT_REVIEWS" bash "$ROOT/bin/sift" w3-verdict s3 "$STAGE" >/dev/null 2>&1 \
  || fail "'sift w3-verdict' failed to land a well-formed staged verdict"
[ -f "$SIFT_REVIEWS/s3.w3.json" ] || fail "verb did not write the canonical .harness/reviews/s3.w3.json artifact"
SIFT_W3_REQUIRE_HOST_VERDICT=1 SIFT_REVIEWS="$SIFT_REVIEWS" SIFT_REPO_ROOT="$ROOT" bash "$W3" "$PK" s3 >/dev/null 2>&1 \
  || fail "host-mode W3 did not accept the verdict the verb landed"

# ---- 4. a malformed / double-verdict staging file is REFUSED ---------------------------
BAD="$T/bad.w3.json"
printf '%s' '{"verdict":"pass","confidence":0.9,"rubric":{"R1":"pass"}}{"verdict":"reject"}' > "$BAD"
if SIFT_REPO_ROOT="$T" SIFT_REVIEWS="$T/.harness/reviews2" bash "$ROOT/bin/sift" w3-verdict s4 "$BAD" >/dev/null 2>&1; then
  fail "'sift w3-verdict' accepted a double-verdict (injection) staging file — must fail closed"
fi
# fail-closed BEFORE writing: a rejected double-verdict must land NO canonical artifact
# (a verb that rejects-after-writing would leave a poisoned s4.w3.json a later W3 reads).
[ ! -e "$T/.harness/reviews2/s4.w3.json" ] \
  || fail "'sift w3-verdict' landed an artifact despite rejecting a double-verdict — must fail closed before writing, not clean up after"

# ---- 5. the validated bytes are the LANDED bytes (no validate-then-reland TOCTOU) ---------
# The verb snapshots the staging bytes into a sift-owned temp under the reviews dir (which the
# scope guard denies the agent), then validates AND lands that snapshot. Two locks on that:
# (a) no staging snapshot is ever left behind (on land OR on refuse), and (b) an oversized
# staging file is refused before it can be read or landed.
ls "$SIFT_REVIEWS"/*.w3.stage >/dev/null 2>&1 \
  && fail "w3-verdict left a staging snapshot in the reviews dir (must be removed on every exit path)"
ls "$T/.harness/reviews2"/*.w3.stage >/dev/null 2>&1 \
  && fail "w3-verdict left a staging snapshot after a refused verdict"

BIG="$T/big.w3.json"
python3 -c 'open("'"$BIG"'","w").write("{\"verdict\":\"pass\",\"confidence\":0.9,\"rubric\":{},\"pad\":\""+"A"*70000+"\"}")'
if SIFT_REPO_ROOT="$T" SIFT_REVIEWS="$T/.harness/reviews3" bash "$ROOT/bin/sift" w3-verdict s5 "$BIG" >/dev/null 2>&1; then
  fail "'sift w3-verdict' accepted an oversized staging file — must bound staging size"
fi
[ ! -e "$T/.harness/reviews3/s5.w3.json" ] || fail "oversized staging file landed an artifact"

echo "PASS: w3-verdict lands an in-scope verdict past the fence (sift's own write); direct .harness write stays denied; malformed/oversized input refused without landing an artifact; no staging snapshot leaks"
