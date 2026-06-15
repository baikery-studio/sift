#!/usr/bin/env bash
# Acceptance for ORCH-4-DECISION-TRACE. RED on HEAD: there is no sanctioned orchestrator
# decision-trace reader — `sift trace <wid>` does not exist (bin/sift fail-soft no-ops the
# unknown subcommand), and no kernel/orchestrate.sh emit surface. A driver's rationale cannot
# be surfaced. Proves: `sift trace <wid>` surfaces a wave's orchestrator decisions; AND the
# above-core boundary holds — injecting arbitrary orch.* events leaves a confirmed packet
# confirmed and the chain verifying (the GREEN-guard invariant, already true on HEAD, so it
# locks the boundary but is NOT the RED).
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS 2>/dev/null || true

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export SIFT_REPO_ROOT="$W" SIFT_LOG="$W/.harness/log.jsonl" SIFT_REVIEWS="$W/.harness/reviews"
mkdir -p "$SIFT_REVIEWS"; . "$ROOT/kernel/log.sh"; . "$ROOT/kernel/state.sh"
_sha(){ python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# Build a genuine witness-bound confirmed for packet $1 (TRUST-AUDIT-1 pattern).
mkconfirmed(){ local P="$1"
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
  we="$(python3 -c 'import json,sys;print(json.dumps({"verdict_event":sys.argv[1],"feature_sha":"abc","extended_hash":sys.argv[5],"w1_ok":True,"w2_hash":sys.argv[2],"w3_hash":sys.argv[3],"w4_hash":sys.argv[4]}))' "$veh" "$h2" "$h3" "$h4" "$eh")"
  log_append lane.transition reviewing confirmed "$P" "$we" >/dev/null
}
mkconfirmed dm1
[ "$(SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" state dm1 2>/dev/null)" = confirmed ] \
  || fail "scaffold broken: dm1 is not confirmed"

# ---- GREEN GUARD (already holds on HEAD; NOT the RED): orch.* events are inert -----------
# A driver WOULD log these. Emit decisions for TWO different waves (orchw + orchx) onto the
# same chain, incl. an unknown orch.* kind. The wave-distinguishing tokens (next=dm1 for
# orchw vs next=ZZZ for orchx) let the RED prove the reader FILTERS by wave, not cats the log.
SIFT_ACTOR=orchestrator log_append orch.decision _ _ "__wave__:orchw" '{"action":"dispatch","reason":"next=dm1"}' >/dev/null
SIFT_ACTOR=orchestrator log_append packet.emit   _ _ "__wave__:orchw" '{"packet":"dm2","reason":"coverage gap on req-2"}' >/dev/null
SIFT_ACTOR=orchestrator log_append orch.bogus    _ _ "__wave__:orchw" '{"x":1}' >/dev/null
SIFT_ACTOR=orchestrator log_append orch.decision _ _ "__wave__:orchx" '{"action":"dispatch","reason":"next=ZZZ_otherwave"}' >/dev/null
[ "$(SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" state dm1 2>/dev/null)" = confirmed ] \
  || fail "BOUNDARY BROKEN: orch.* events moved a confirmed packet's state (above-core boundary violated)"
SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" verify-log >/dev/null 2>&1 \
  || fail "BOUNDARY BROKEN: orch.* events broke the hash-chain"

# ---- PRIMARY RED: a sanctioned reader must surface THIS wave's decision trace, FILTERED ---
out="$(SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" trace orchw 2>/dev/null || true)"
printf '%s' "$out" | grep -q 'orch.decision' \
  || fail "'sift trace' did not surface the orch.decision events (RED: no orchestrator decision-trace reader — bin/sift fail-soft no-ops 'trace')"
printf '%s' "$out" | grep -q 'packet.emit' \
  || fail "'sift trace' did not surface the packet.emit events (RED: reader missing)"
printf '%s' "$out" | grep -q 'next=dm1' \
  || fail "'sift trace orchw' did not surface orchw's own decision reason (RED: reader not reading event content)"
# FILTER PROOF: orchx's decision must NOT appear in orchw's trace — defeats a cat/grep-the-log cheat.
printf '%s' "$out" | grep -q 'ZZZ_otherwave' \
  && fail "'sift trace orchw' leaked another wave's (orchx) decision — reader does not filter by wave (cat/grep cheat)"

# ---- SANCTIONED EMIT: sift_orch_log must land a REAL JSON reason payload (not just log_append).
# The driver (ORCH-1/2/3) emits via sift_orch_log, so it must round-trip a real payload and
# refuse a state-affecting kind. (Guards the brace-default bug where a '{...}' reason corrupts.)
( . "$ROOT/kernel/orchestrate.sh"
  SIFT_REPO_ROOT="$W" SIFT_LOG="$W/.harness/log.jsonl" sift_orch_log emitw orch.decision '{"action":"dispatch","reason":"next=via_helper"}' ) \
  || fail "sift_orch_log failed to emit a real JSON reason payload (the sanctioned emit must round-trip {...} JSON)"
SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" verify-log >/dev/null 2>&1 \
  || fail "sift_orch_log broke the chain"
out_emit="$(SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" trace emitw 2>/dev/null || true)"
printf '%s' "$out_emit" | grep -q 'next=via_helper' \
  || fail "sift_orch_log's payload did not round-trip into the trace (brace-default corruption?)"
# the sanctioned emit must REFUSE a state-affecting kind (else it could bypass the boundary).
if ( . "$ROOT/kernel/orchestrate.sh"; SIFT_REPO_ROOT="$W" SIFT_LOG="$W/.harness/log.jsonl" sift_orch_log emitw lane.transition '{}' ) >/dev/null 2>&1; then
  fail "sift_orch_log accepted kind 'lane.transition' — the sanctioned emit must refuse state-affecting kinds"
fi

echo "PASS: orch decisions ride the chain inert to state (boundary locked); 'sift trace' surfaces THIS wave's decisions and filters out other waves'; sift_orch_log round-trips a real JSON payload and refuses state-affecting kinds"
