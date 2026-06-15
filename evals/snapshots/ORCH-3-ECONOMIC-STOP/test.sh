#!/usr/bin/env bash
# Acceptance for ORCH-3-ECONOMIC-STOP. RED on HEAD: there is NO stopping governor — no
# 'kernel/drive.sh', no 'sift_drive_governor', no retry-ceiling or no-progress detector
# anywhere in kernel/. An unguarded drive loop (ORCH-1-DRIVE-LOOP) would re-dispatch a
# wedged packet forever (executing->failed->executing->failed... is a legal cycle).
#
# The fix ships a governor in 'kernel/drive.sh' that COUNTS a packet's failed transitions
# (executing->failed + reviewing->review_failed) from the HASH-CHAINED, verified log and,
# at >= the packet's max_retries, emits a chained orch.decision{reason:retry_ceiling}
# and STOPS driving it. Guards: a packet under the ceiling does NOT halt; the governor
# refuses to halt/supersede an already-confirmed packet; the emitted decision is INERT to
# state projection (it cannot fabricate a terminal). Zero egress is preserved.
#
# This RED targets a MISSING CAPABILITY (the governor verb/function), exercised
# behaviorally — NOT an invariant that already holds. The "decision is inert to state"
# property IS already true on HEAD and is asserted only as a GREEN-guard co-assertion
# (so an over-broad fix that wires orchestrator.* into _state.py is caught), never as the
# primary RED.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS 2>/dev/null || true

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export SIFT_REPO_ROOT="$W" SIFT_LOG="$W/.harness/log.jsonl" SIFT_REVIEWS="$W/.harness/reviews"
mkdir -p "$SIFT_REVIEWS"
. "$ROOT/kernel/log.sh"; . "$ROOT/kernel/state.sh"
_sha(){ python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# Count this packet's FAILED transitions from the CHAINED log (executing->failed +
# reviewing->review_failed). Mirrors what the governor must derive from the verified chain.
count_failed(){ python3 -c '
import json,sys
P=sys.argv[2]; n=0
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if not ln: continue
    e=json.loads(ln)
    if e.get("packet_id")!=P or e.get("kind")!="lane.transition": continue
    f,t=e.get("from"),e.get("to")
    if (f,t) in (("executing","failed"),("reviewing","review_failed")): n+=1
print(n)' "$SIFT_LOG" "$1"; }

# Is there a chained orch.decision{reason:retry_ceiling} for packet $1?
has_halt_decision(){ python3 -c '
import json,sys
P=sys.argv[2]; ok=1
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if not ln: continue
    e=json.loads(ln)
    if e.get("packet_id")==P and e.get("kind")=="orch.decision":
        we=e.get("witness_evidence") or {}
        if we.get("reason")=="retry_ceiling" and we.get("action")=="halt": ok=0
sys.exit(ok)' "$SIFT_LOG" "$1"; }

# Build a wedged packet: max_retries+1 executing->failed transitions (small ceiling = 2).
CEIL=2
P=wedged
log_append lane.transition submitted packeted  "$P" >/dev/null
log_append lane.transition packeted  executing "$P" >/dev/null
log_append lane.transition executing failed    "$P" >/dev/null
log_append lane.transition failed    executing "$P" >/dev/null
log_append lane.transition executing failed    "$P" >/dev/null
log_append lane.transition failed    executing "$P" >/dev/null
log_append lane.transition executing failed    "$P" >/dev/null

# ---- 0. SANITY: the scaffold is sound BEFORE we exercise the missing capability. --------
bash "$ROOT/bin/sift" verify-log >/dev/null 2>&1 \
  || fail "scaffold broken: the constructed retry-loop log does not chain-verify"
[ "$(project_state "$P")" = failed ] \
  || fail "scaffold broken: the wedged packet did not project to 'failed' (got $(project_state "$P"))"
[ "$(count_failed "$P")" -gt "$CEIL" ] \
  || fail "scaffold broken: expected > $CEIL failed transitions, counted $(count_failed "$P")"
# No halt decision exists yet (nothing has run the governor).
has_halt_decision "$P" \
  && fail "scaffold broken: a retry_ceiling decision already exists before the governor ran"

# ---- 1. PRIMARY RED: the governor must EXIST and HALT a packet at its retry ceiling. -----
# On HEAD this fails: 'kernel/drive.sh' and 'sift_drive_governor' do not exist. The governor
# is the MISSING capability — counted from the verified chain, it must emit a chained
# orch.decision{reason:retry_ceiling} and signal HALT (non-zero) for the wedged packet.
[ -f "$ROOT/kernel/drive.sh" ] \
  || fail "no 'kernel/drive.sh' — the stopping governor does not exist (RED: add sift_drive_governor counting failed transitions vs max_retries)"
# shellcheck source=/dev/null
. "$ROOT/kernel/drive.sh" 2>/dev/null \
  || fail "could not source 'kernel/drive.sh' (RED: governor not implemented)"
command -v sift_drive_governor >/dev/null 2>&1 \
  || fail "no 'sift_drive_governor' function in kernel/drive.sh (RED: per-packet retry-ceiling governor missing)"

# Invoke the governor at the ceiling. Contract: it returns NON-ZERO (halt) for a packet at
# or over its ceiling, and logs the chained decision.
if sift_drive_governor "$P" "$CEIL" >/dev/null 2>&1; then
  fail "governor did NOT halt a packet with $(count_failed "$P") failed transitions vs ceiling $CEIL (RED: no retry-ceiling — an unguarded loop retries a wedged packet forever)"
fi
has_halt_decision "$P" \
  || fail "governor halted but logged NO chained orch.decision{reason:retry_ceiling} (the halt must ride the tamper-evident chain, not just a console line)"
bash "$ROOT/bin/sift" verify-log >/dev/null 2>&1 \
  || fail "the orch.decision broke the hash-chain (it must be a normal chained event)"

# ---- 2. GUARD: a packet UNDER the ceiling does NOT halt and logs NO decision. ------------
PU=below
log_append lane.transition submitted packeted  "$PU" >/dev/null
log_append lane.transition packeted  executing "$PU" >/dev/null
log_append lane.transition executing failed    "$PU" >/dev/null   # 1 failure, ceiling 2
[ "$(count_failed "$PU")" -lt "$CEIL" ] \
  || fail "scaffold broken: 'below' packet should be under the ceiling"
if ! sift_drive_governor "$PU" "$CEIL" >/dev/null 2>&1; then
  fail "governor HALTED a packet under its ceiling ($(count_failed "$PU")/$CEIL) — false stop (must only halt at >= max_retries)"
fi
has_halt_decision "$PU" \
  && fail "governor logged a retry_ceiling decision for a packet under the ceiling (must emit NOTHING below the ceiling)"

# ---- 3. GUARD: the governor REFUSES to halt/supersede an ALREADY-CONFIRMED packet. -------
# A brake must never erase or contradict a real, witness-bound completion.
PC=done
printf '{"verdict":"pass","confidence":0.9}\n' > "$SIFT_REVIEWS/$PC.w3.json"
printf '{"w2":"reproduced"}\n'                 > "$SIFT_REVIEWS/$PC.w2.json"
printf '{"ok":true}\n'                          > "$SIFT_REVIEWS/$PC.w4.json"
printf 'pkt %s\n' "$PC"                         > "$SIFT_REVIEWS/$PC.packet"
h2=$(_sha "$SIFT_REVIEWS/$PC.w2.json"); h3=$(_sha "$SIFT_REVIEWS/$PC.w3.json")
h4=$(_sha "$SIFT_REVIEWS/$PC.w4.json"); eh=$(_sha "$SIFT_REVIEWS/$PC.packet")
log_append lane.transition submitted     packeted       "$PC" >/dev/null
log_append lane.transition packeted       executing      "$PC" >/dev/null
log_append lane.transition executing      acceptance_met "$PC" >/dev/null
log_append lane.transition acceptance_met reviewing      "$PC" >/dev/null
vj="$(python3 -c 'import json,sys; print(json.dumps({"verdict":"pass","feature_sha":"abc","w1_ok":True,"w2_hash":sys.argv[1],"w3_hash":sys.argv[2],"w4_hash":sys.argv[3]}))' "$h2" "$h3" "$h4")"
veh="$(log_append review.verdict reviewing reviewing "$PC" "$vj")"
we="$(python3 -c 'import json,sys; print(json.dumps({"verdict_event":sys.argv[1],"feature_sha":"abc","extended_hash":sys.argv[5],"w1_ok":True,"w2_hash":sys.argv[2],"w3_hash":sys.argv[3],"w4_hash":sys.argv[4]}))' "$veh" "$h2" "$h3" "$h4" "$eh")"
log_append lane.transition reviewing confirmed "$PC" "$we" >/dev/null
[ "$(project_state "$PC")" = confirmed ] \
  || fail "scaffold broken: did not build a genuine confirmed for the refusal guard"
# Even with a huge synthetic ceiling of 0 (trivially exceeded), a confirmed must NOT be halted.
sift_drive_governor "$PC" 0 >/dev/null 2>&1 \
  || fail "governor returned a halt/error for an already-confirmed packet (RED: must refuse to govern a confirmed — a brake may never touch a witness-bound completion)"
has_halt_decision "$PC" \
  && fail "governor logged a retry_ceiling decision against an already-confirmed packet (must never halt/supersede a confirmed)"
[ "$(project_state "$PC")" = confirmed ] \
  || fail "the governor changed an already-confirmed packet's state to $(project_state "$PC") (a stop must NEVER mutate a confirmed)"

# ---- 4. CORE-SAFETY co-assertion: the decision is INERT to state projection. ------------
# (Already true on HEAD — this guards an over-broad fix that wires orchestrator.* into the
# replay. Re-check the wedged packet AFTER its halt decision was logged: state unchanged.)
[ "$(project_state "$P")" = failed ] \
  || fail "the orch.decision MOVED state (wedged packet is now $(project_state "$P")) — decisions must be INERT to _state.py replay; a halt must never fabricate a terminal"
# _state.py must NOT have been taught to consume orch.* (it binds only lane.transition +
# review.verdict). Target the KIND namespace, not the actor word: the actor "orchestrator"
# is fine; only consuming an orch.* event KIND in the replay would let a halt fabricate state.
grep -qE 'orch\.(decision|stop|emit|bogus)|kind.*orch' "$ROOT/kernel/_state.py" \
  && fail "_state.py references an orch.* event kind — the replay must NOT consume orch.* events (that would let a halt fabricate state). Keep decisions inert."

# ---- 5. zero egress preserved. ----------------------------------------------------------
bash "$ROOT/tests/test-no-egress.sh" >/dev/null 2>&1 || fail "test-no-egress.sh regressed"

echo "PASS: economic-stop governor halts at the retry ceiling (chained orch.decision{retry_ceiling}), does NOT halt below the ceiling, refuses an already-confirmed packet, and its decision is INERT to state projection; zero egress preserved"
