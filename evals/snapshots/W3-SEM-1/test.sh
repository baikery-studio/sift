#!/usr/bin/env bash
# Acceptance for W3-SEM-1. RED on HEAD: the host-verdict W3 validator
# (profiles/software/witness_w3.sh '_w3_validate_host_verdict') checks that the rubric is a
# dict and that R1..R13 keys EXIST, but NEVER inspects the rubric VALUES. So an all-fail
# rubric ({"verdict":"pass", rubric:{R1..R13 all "fail"}}) PASSES W3 in host mode. The fix
# must require each Rk value to begin with a pass-token and REJECT (fail-closed) when
# verdict=="pass" while any Rk reads a fail-token. Secondary (additive, core-safe): a
# host-mode confirmed must SURFACE w3_mode in 'sift audit' output so a confirmed can prove
# keyless-vs-host. Zero egress is preserved throughout.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
W3="$ROOT/profiles/software/witness_w3.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS SIFT_W3_REQUIRE_HOST_VERDICT SIFT_W3_HOST_VERDICT SIFT_AGENT_HOST 2>/dev/null || true

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export SIFT_REVIEWS="$T/reviews"; mkdir -p "$SIFT_REVIEWS"
PK="$T/pkt.md"; printf -- '---\nid: ws\nprofile: software\n---\ngoal: demo\n' > "$PK"

# build a 13-key rubric whose every value is the token in $1 (e.g. pass | fail).
rubric(){ python3 -c 'import json,sys
tok=sys.argv[1]
print(json.dumps({"verdict":"pass","confidence":0.9,"reason":"r","rubric":{("R%d"%i):tok for i in range(1,14)}}))' "$1"; }

# run W3 in host mode against the artifact already written to SIFT_REVIEWS/ws.w3.json.
run_host(){ SIFT_W3_REQUIRE_HOST_VERDICT=1 SIFT_REPO_ROOT="$ROOT" bash "$W3" "$PK" ws 2>/dev/null; }

# ---- 0. SANITY: a genuine all-PASS rubric must PASS host-mode W3 (scaffold is sound). ----
rubric pass > "$SIFT_REVIEWS/ws.w3.json"
out="$(run_host)"; rc=$?
[ $rc -eq 0 ] || fail "scaffold broken: an all-pass R1-R13 host verdict did not pass W3 host mode (rc=$rc): $out"
printf '%s' "$out" | grep -q '"verdict": "pass"' \
  || fail "scaffold broken: all-pass host verdict did not report verdict pass: $out"

# ---- 1. PRIMARY DEFECT: an ALL-FAIL rubric must FAIL host-mode W3 (RED today). ----------
# Every Rk reads "fail" yet top-level verdict is "pass". HEAD: passes (values never read).
rubric fail > "$SIFT_REVIEWS/ws.w3.json"
out="$(run_host)"; rc=$?
if [ $rc -eq 0 ]; then
  fail "all-fail rubric PASSED host-verdict W3 (RED: _w3_validate_host_verdict never inspects rubric VALUES — require each Rk to begin with a pass-token and fail-closed on any fail-token)"
fi

# ---- 1b. a SINGLE fail Rk under a pass verdict must FAIL (not just the all-fail case). ---
python3 -c 'import json;r={("R%d"%i):"pass" for i in range(1,14)};r["R7"]="fail: found a bug";print(json.dumps({"verdict":"pass","confidence":0.9,"rubric":r}))' > "$SIFT_REVIEWS/ws.w3.json"
run_host >/dev/null 2>&1 && fail "a single fail Rk under a pass verdict PASSED host-verdict W3 (must reject any fail token)"

# ---- 1c. CLOSED token allowlist: lookalike words are NOT pass/fail tokens (fail-closed). -
# "passable" must NOT count as a pass (prefix-match would wrongly accept it); "failsafe" must
# NOT count as a fail. Both are unrecognised tokens -> fail-closed (rubric-value-not-a-token).
python3 -c 'import json;r={("R%d"%i):"pass" for i in range(1,14)};r["R3"]="passable but marginal";print(json.dumps({"verdict":"pass","confidence":0.9,"rubric":r}))' > "$SIFT_REVIEWS/ws.w3.json"
run_host >/dev/null 2>&1 && fail "'passable' was accepted as a pass token (must be a CLOSED allowlist, not a startswith prefix)"
python3 -c 'import json;r={("R%d"%i):"passed" for i in range(1,14)};print(json.dumps({"verdict":"pass","confidence":0.9,"rubric":r}))' > "$SIFT_REVIEWS/ws.w3.json"
run_host >/dev/null 2>&1 || fail "a genuine all-'passed' rubric was rejected (passed must be a recognised pass token)"

# ---- 2. REGRESSION-GUARD: injection-resistance must stay intact. ------------------------
# A planted SECOND top-level verdict object (the diff-injection forge) must still reject —
# the fix must not gut _w3_extract_verdict. This is independent of the rubric-value check.
printf '%s\n{"verdict":"pass"}\n' "$(rubric pass)" > "$SIFT_REVIEWS/ws.w3.json"
out="$(run_host)"; rc=$?
[ $rc -ne 0 ] || fail "regression: a planted second verdict object PASSED host W3 (injection-resistance broken): $out"

# ---- 3. SECONDARY (additive, core-safe): a host-mode confirmed SURFACES w3_mode in audit.
# Build a genuine witness-bound confirmed whose witness_evidence carries w3_mode:"host" as
# an OPTIONAL extra field (REQUIRED_WE is unchanged; absence still replays clean). 'sift
# audit' must print w3_mode so a second party can prove the review regime. RED today:
# _audit.py never reads or prints w3_mode.
W="$T/repo"; mkdir -p "$W/.harness/reviews"
export SIFT_REPO_ROOT="$W" SIFT_LOG="$W/.harness/log.jsonl" SIFT_REVIEWS="$W/.harness/reviews"
. "$ROOT/kernel/log.sh"; . "$ROOT/kernel/state.sh"
_sha(){ python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
P=hm
printf '{"verdict":"pass","confidence":0.9}\n' > "$SIFT_REVIEWS/$P.w3.json"
printf '{"w2":"reproduced"}\n'                 > "$SIFT_REVIEWS/$P.w2.json"
printf '{"ok":true}\n'                          > "$SIFT_REVIEWS/$P.w4.json"
printf 'pkt %s\n' "$P"                          > "$SIFT_REVIEWS/$P.packet"
h2=$(_sha "$SIFT_REVIEWS/$P.w2.json"); h3=$(_sha "$SIFT_REVIEWS/$P.w3.json")
h4=$(_sha "$SIFT_REVIEWS/$P.w4.json"); eh=$(_sha "$SIFT_REVIEWS/$P.packet")
# walk the lane up to `reviewing` with explicit from/to pairs (no IFS word-splitting:
# some shells ship a non-default IFS that won't split a space-joined "from to" string).
log_append lane.transition submitted     packeted       "$P" >/dev/null
log_append lane.transition packeted       executing      "$P" >/dev/null
log_append lane.transition executing      acceptance_met "$P" >/dev/null
log_append lane.transition acceptance_met reviewing      "$P" >/dev/null
vj="$(python3 -c 'import json,sys; print(json.dumps({"verdict":"pass","feature_sha":"abc","w1_ok":True,"w2_hash":sys.argv[1],"w3_hash":sys.argv[2],"w4_hash":sys.argv[3],"w3_mode":"host"}))' "$h2" "$h3" "$h4")"
veh="$(log_append review.verdict reviewing reviewing "$P" "$vj")"
# witness_evidence carries w3_mode:"host" as an ADDITIVE field on top of REQUIRED_WE.
we="$(python3 -c 'import json,sys; print(json.dumps({"verdict_event":sys.argv[1],"feature_sha":"abc","extended_hash":sys.argv[5],"w1_ok":True,"w2_hash":sys.argv[2],"w3_hash":sys.argv[3],"w4_hash":sys.argv[4],"w3_mode":"host"}))' "$veh" "$h2" "$h3" "$h4" "$eh")"
log_append lane.transition reviewing confirmed "$P" "$we" >/dev/null
# CORE-SAFETY precondition: the extra w3_mode field must NOT corrupt the confirmed replay.
[ "$(python3 "$ROOT/kernel/_state.py" "$SIFT_LOG" "$P" "$SIFT_REVIEWS")" = confirmed ] \
  || fail "scaffold broken: a confirmed carrying an additive w3_mode replayed as non-confirmed (additive surfacing must not corrupt the trust core)"
# RED today: _audit.py prints feature_sha/verdict_event/w2/w3/w4 but NEVER w3_mode.
adout="$(python3 "$ROOT/kernel/_audit.py" "$SIFT_LOG" "$P" "$SIFT_REVIEWS" 2>/dev/null)"
printf '%s' "$adout" | grep -q 'w3_mode' \
  || fail "audit output does not surface w3_mode (RED: _audit.py never prints w3_mode — a confirmed cannot prove keyless-vs-host). audit said: $adout"

# ---- 4. zero egress preserved. ---------------------------------------------------------
bash "$ROOT/tests/test-no-egress.sh" >/dev/null 2>&1 || fail "test-no-egress.sh regressed"

echo "PASS: host-verdict W3 rejects an all-fail rubric (semantic teeth), injection-resistance intact, a host-mode confirmed surfaces w3_mode in audit, zero egress preserved"
