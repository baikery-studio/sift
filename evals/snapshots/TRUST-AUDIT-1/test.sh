#!/usr/bin/env bash
# Acceptance for TRUST-AUDIT-1. RED on HEAD: kernel/_audit.py is NOT self-sufficient —
# invoked directly it only re-hashes the 3 artifacts, so it PASSES a tampered chain AND a
# forged witness-binding (it trusts audit.sh to have run verify_log_chain + project_state
# first). Also: a witness-bound partially_confirmed is unauditable (audit.sh:24 gates on
# st==confirmed; _audit.py:32 and doctor.sh scan only to==confirmed). Proves: _audit.py
# refuses a tampered/forged confirmed ON ITS OWN, and 'sift audit' accepts a genuine
# partially_confirmed and reports its grade.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS 2>/dev/null || true

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export SIFT_REPO_ROOT="$W" SIFT_LOG="$W/.harness/log.jsonl" SIFT_REVIEWS="$W/.harness/reviews"
mkdir -p "$SIFT_REVIEWS"; . "$ROOT/kernel/log.sh"; . "$ROOT/kernel/state.sh"
_sha(){ python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# Build a witness-bound terminal (to = confirmed | partially_confirmed) for packet $1.
# verdict_event override ($3, optional) lets us forge the binding (point at no real verdict).
mkterminal(){ local P="$1" TO="$2" VE_OVERRIDE="${3:-}"
  printf '{"verdict":"pass","confidence":0.9}\n' > "$SIFT_REVIEWS/$P.w3.json"
  printf '{"w2":"reproduced"}\n'                 > "$SIFT_REVIEWS/$P.w2.json"
  printf '{"ok":true}\n'                          > "$SIFT_REVIEWS/$P.w4.json"
  printf 'pkt %s\n' "$P"                          > "$SIFT_REVIEWS/$P.packet"
  local h2 h3 h4 eh; h2=$(_sha "$SIFT_REVIEWS/$P.w2.json"); h3=$(_sha "$SIFT_REVIEWS/$P.w3.json")
  h4=$(_sha "$SIFT_REVIEWS/$P.w4.json"); eh=$(_sha "$SIFT_REVIEWS/$P.packet")
  for e in "submitted packeted" "packeted executing" "executing acceptance_met" "acceptance_met reviewing"; do
    set -- $e; log_append lane.transition "$1" "$2" "$P" >/dev/null; done
  local vj veh we
  vj="$(python3 -c 'import json,sys;print(json.dumps({"verdict":"pass","feature_sha":"abc","w2_hash":sys.argv[1],"w3_hash":sys.argv[2],"w4_hash":sys.argv[3]}))' "$h2" "$h3" "$h4")"
  veh="$(log_append review.verdict reviewing reviewing "$P" "$vj")"
  [ -n "$VE_OVERRIDE" ] && veh="$VE_OVERRIDE"
  we="$(python3 -c 'import json,sys;print(json.dumps({"verdict_event":sys.argv[1],"feature_sha":"abc","extended_hash":sys.argv[5],"w1_ok":True,"w2_hash":sys.argv[2],"w3_hash":sys.argv[3],"w4_hash":sys.argv[4]}))' "$veh" "$h2" "$h3" "$h4" "$eh")"
  log_append lane.transition reviewing "$TO" "$P" "$we" >/dev/null
}

# ---- 1. SELF-SUFFICIENCY vs a TAMPERED CHAIN -------------------------------------------
mkterminal good confirmed
SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" audit good >/dev/null 2>&1 \
  || fail "scaffold broken: 'sift audit' rejected a genuine confirmed"
# Break the chain: mutate a content field of line 1 WITHOUT recomputing its event_hash.
python3 - "$SIFT_LOG" <<'PY'
import sys, json
p = sys.argv[1]; lines = open(p).read().splitlines()
e = json.loads(lines[0]); e["actor"] = e.get("actor", "x") + "_TAMPER"
lines[0] = json.dumps(e, separators=(',', ':'), ensure_ascii=False)
open(p, "w").write("\n".join(lines) + "\n")
PY
bash "$ROOT/bin/sift" verify-log >/dev/null 2>&1 \
  && fail "scaffold broken: tamper did not break the chain"
# _audit.py INVOKED DIRECTLY must now FAIL. RED today: it PASSES (re-hashes artifacts only).
if python3 "$ROOT/kernel/_audit.py" "$SIFT_LOG" good "$SIFT_REVIEWS" >/dev/null 2>&1; then
  fail "_audit.py PASSED a tampered chain on its own (RED: not self-sufficient — inline chain-verify + project_state)"
fi

# ---- 2. SELF-SUFFICIENCY vs a FORGED WITNESS-BINDING -----------------------------------
# Fresh log; a confirmed whose witness_evidence.verdict_event points at no real verdict.
rm -f "$SIFT_LOG"; mkdir -p "$SIFT_REVIEWS"
FAKE_VE="$(python3 -c 'print("f"*64)')"
mkterminal forged confirmed "$FAKE_VE"
# The real path already rejects this (project_state -> corrupt):
bash "$ROOT/bin/sift" verify-log >/dev/null 2>&1 \
  || fail "scaffold broken: forged-binding log should still chain-verify (semantic forge, not structural)"
# _audit.py INVOKED DIRECTLY must FAIL. RED today: it never checks verdict_event, so PASSES.
if python3 "$ROOT/kernel/_audit.py" "$SIFT_LOG" forged "$SIFT_REVIEWS" >/dev/null 2>&1; then
  fail "_audit.py PASSED a forged witness-binding on its own (RED: never validates verdict_event reference)"
fi

# ---- 3. partially_confirmed IS AUDITABLE -----------------------------------------------
rm -f "$SIFT_LOG"; mkdir -p "$SIFT_REVIEWS"
mkterminal soft partially_confirmed
[ "$(SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" state soft 2>/dev/null)" = partially_confirmed ] \
  || fail "scaffold broken: did not build a genuine partially_confirmed"
# RED today: audit.sh:24 fails any st != confirmed.
SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" audit soft >/dev/null 2>&1 \
  || fail "'sift audit' rejected a genuine witness-bound partially_confirmed (RED: terminal not generalised)"

echo "PASS: _audit.py is self-sufficient (fails a tampered chain and a forged binding on its own); partially_confirmed is auditable"
