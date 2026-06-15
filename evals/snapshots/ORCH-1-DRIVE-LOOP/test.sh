#!/usr/bin/env bash
# Acceptance for ORCH-1-DRIVE-LOOP. RED on HEAD: there is NO drive loop. bin/sift is a flat
# case dispatcher and 'drive' is not a verb — an unknown subcommand fail-softs (stderr +
# exit 0, no JSON, NO state movement). kernel/drive.sh does not exist. So 'sift drive <wave>'
# advances NOTHING: a wave whose only member is 'submitted' stays 'submitted'. The GREEN
# increment ships 'sift drive <wave>' — a deterministic loop ABOVE the core that reads
# sift_next(wave), dispatches by project_state (submitted->plan, packeted/failed/
# review_failed->execute, acceptance_met->review, crash-stuck reviewing->abort) under the
# dispatch lock, repeating until sift_next==ALL-CONFIRMED then wave-review. This test proves
# the verb EXISTS and ADVANCES a member by its project_state (the missing capability), keeps
# the loop terminating on a missing/ALL-CONFIRMED wave (no infinite spin), and — as a
# GREEN-GUARD co-assertion (NOT the RED) — that the loop never forges state directly: only
# the pipeline's real witnesses may emit lane.transition / review.verdict.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS SIFT_REPO_ROOT SIFT_CONFIG 2>/dev/null || true

# Portable bounded run: no `timeout`/`gtimeout` on stock macOS, so run the command in the
# background and reap it after a deadline. Returns the command's exit code, or 124 if it had
# to be killed (a hung / infinite drive loop). Output is captured to $RUN_OUT.
RUN_OUT=""
run_bounded(){ # <seconds> <cmd...>
  local secs="$1"; shift
  local tmp; tmp="$(mktemp)"
  ( "$@" >"$tmp" 2>&1 ) &
  local cpid=$!
  ( sleep "$secs"; kill -9 "$cpid" 2>/dev/null ) &
  local wpid=$!
  local rc=0
  wait "$cpid" 2>/dev/null; rc=$?
  kill -9 "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null || true
  RUN_OUT="$(cat "$tmp")"; rm -f "$tmp"
  # kill -9 surfaces as 137 (128+9); normalize to 124 = "timed out / had to be killed".
  [ "$rc" = 137 ] && rc=124
  return "$rc"
}

# ---- isolated repo so we never touch the real .harness / waves / packets. ---------------
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export SIFT_REPO_ROOT="$W" \
       SIFT_LOG="$W/.harness/log.jsonl" \
       SIFT_STATE="$W/.harness" \
       SIFT_REVIEWS="$W/.harness/reviews" \
       SIFT_PACKETS="$W/tasks/packets"
mkdir -p "$SIFT_PACKETS" "$SIFT_REVIEWS" "$W/tasks/waves" "$W/.harness"

# a real, plannable toy packet in the default 'submitted' state (no log entries yet).
PK=dm1
cat > "$SIFT_PACKETS/$PK.md" <<EOF
---
schema_version: v1
id: $PK
profile: toy
goal: drive-loop probe member
artifact:
  path: out/$PK.txt
  marker: $PK-OK
scope:
  paths:
    - out/$PK.txt
proof_artifact: {path: evals/snapshots/$PK/proof.json, required_terminal_event: $PK.done}
---
# $PK
EOF

# a one-member wave manifest at the repo's tasks/waves (where next.sh + wave.sh read).
WID=orchw
printf '{"id":"%s","members":["%s"]}\n' "$WID" "$PK" > "$W/tasks/waves/$WID.json"

sift(){ bash "$ROOT/bin/sift" "$@"; }

# ---- 0. SANITY: the scaffold is sound (member submitted, next points at it). -------------
[ "$(sift state "$PK" 2>/dev/null)" = submitted ] \
  || fail "scaffold broken: member '$PK' is not 'submitted' before drive (is '$(sift state "$PK" 2>/dev/null)')"
[ "$(sift next "$WID" 2>/dev/null)" = "$PK" ] \
  || fail "scaffold broken: 'sift next $WID' did not point at the submitted member"

# ---- 1. PRIMARY RED — the MISSING CAPABILITY: 'sift drive <wave>' advances the member. ---
# A drive loop must read sift_next, see 'submitted', and dispatch 'plan' (submitted->packeted)
# under the dispatch lock — at minimum moving the member OFF 'submitted'. HEAD has no 'drive'
# verb (fail-soft no-op), so the member never moves. Bound the run so a GREEN loop bug can't
# hang the suite; treat a kill (124) as a failure too.
run_bounded 30 sift drive "$WID"; drc=$?
[ "$drc" = 124 ] && fail "'sift drive $WID' did not terminate within the deadline (loop must exit at ALL-CONFIRMED, not spin)"
after="$(sift state "$PK" 2>/dev/null)"
if [ "$after" = submitted ]; then
  fail "'sift drive $WID' did not advance the submitted member (still 'submitted'). RED: no 'drive' verb / no kernel/drive.sh — bin/sift fail-soft no-ops an unknown subcommand. drive output was: $RUN_OUT"
fi

# ---- 2. REGRESSION-GUARD (termination): drive of a MISSING wave exits cleanly, no spin. --
# sift_next returns non-zero on a missing manifest; the loop must surface that and STOP, never
# loop forever. (On HEAD this also passes — the no-op returns instantly — so it cannot
# masquerade as the RED; it only fails a GREEN loop that hangs on a non-advancing wave.)
run_bounded 20 sift drive no-such-wave-xyz; nrc=$?
[ "$nrc" = 124 ] && fail "regression: 'sift drive' on a MISSING wave hung (must detect the bad/absent manifest and exit, not loop)"

# ---- 3. GREEN-GUARD CO-ASSERTION (NOT the RED): the loop never FORGES state directly. ----
# The load-bearing trust invariant: only the pipeline's real witnesses may emit
# lane.transition / review.verdict; a drive loop is ABOVE the core and must move state ONLY
# by calling plan/execute/review (which run the witnesses). So NO lane.transition or
# review.verdict event in the post-drive log may carry actor=='orchestrator'. This already
# holds on HEAD (HEAD writes no orch events at all), so it can never stand in for the RED — it
# only catches a GREEN driver that shortcuts the witnesses by minting state events itself.
if [ -f "$SIFT_LOG" ]; then
  forged="$(python3 - "$SIFT_LOG" <<'PY'
import json,sys
bad=0
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if not ln: continue
    try: e=json.loads(ln)
    except Exception: continue
    if e.get("kind") in ("lane.transition","review.verdict") and e.get("actor")=="orchestrator":
        bad+=1
print(bad)
PY
)"
  [ "$forged" = 0 ] \
    || fail "trust-core violation: the drive loop emitted $forged state-moving event(s) (lane.transition/review.verdict) as actor=orchestrator — only the pipeline's witnesses may move state; the loop must dispatch plan/execute/review, never forge transitions"
fi

echo "PASS: 'sift drive $WID' exists and advances a member by project_state (was submitted, now $after); terminates on a missing wave; never forges lane.transition/review.verdict directly"
