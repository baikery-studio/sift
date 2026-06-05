#!/usr/bin/env bash
# Trust-core proof for the spine goal: hash-chain + causal replay + witness-binding.
# Proves the three goal assertions at the kernel level (before bin/sift exists):
#   A. a packet reaches `confirmed` only WITH a valid witness-evidence binding
#   B. `confirmed` reconstructs from log.jsonl alone (compaction survival)
#   C. a legal-chain `...→confirmed` with no/forged witness → `corrupt`
#   D. a tampered committed line → chain verification fails (tamper-evidence)
set -euo pipefail
KDIR="$(cd "$(dirname "$0")/../kernel" && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"
export SIFT_REPO_ROOT="$work" SIFT_LOG="$work/.harness/log.jsonl" SIFT_REVIEWS="$work/.harness/reviews"
mkdir -p "$SIFT_REVIEWS"
. "$KDIR/log.sh"; . "$KDIR/state.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }

P=toy-001
log_append lane.transition submitted     packeted       "$P" >/dev/null
log_append lane.transition packeted       executing      "$P" >/dev/null
log_append lane.transition executing      acceptance_met "$P" >/dev/null
log_append lane.transition acceptance_met reviewing      "$P" >/dev/null
# review.sh writes the FRESH W3 artifact, emits a CHAINED review.verdict event,
# then binds the confirmed event to that event by its event_hash (MP1-TRUST-CORE).
printf '{"verdict":"pass","confidence":0.9}\n' > "$SIFT_REVIEWS/$P.w3.json"
w3h=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$SIFT_REVIEWS/$P.w3.json")
VJ=$(python3 -c 'import json,sys;print(json.dumps({"verdict":"pass","feature_sha":"abc123","w1_ok":True,"w2_ok":True,"w4_ok":True,"w3_hash":sys.argv[1]}))' "$w3h")
VEH=$(log_append review.verdict reviewing reviewing "$P" "$VJ")
WE=$(python3 -c 'import json,sys;print(json.dumps({"verdict_event":sys.argv[1],"feature_sha":"abc123","extended_hash":"def456","w1_ok":True,"w2_hash":"w2","w3_hash":sys.argv[2],"w4_hash":"w4"}))' "$VEH" "$w3h")
log_append lane.transition reviewing confirmed "$P" "$WE" >/dev/null

verify_log_chain >/dev/null || fail "legit log must verify"
[ "$(project_state "$P")" = confirmed ] || fail "witnessed packet must be confirmed"
echo "PASS A: witnessed packet → confirmed"

# B. fresh re-derivation from the log alone (no in-memory state)
[ "$(project_state "$P")" = confirmed ] || fail "must rebuild confirmed from log alone"
echo "PASS B: confirmed reconstructs from log.jsonl alone (compaction-survival)"

# C. legal-chain forge: every edge legal + validly chained, but NO witness ran
P2=forge-legal
log_append lane.transition submitted     packeted       "$P2" >/dev/null
log_append lane.transition packeted       executing      "$P2" >/dev/null
log_append lane.transition executing      acceptance_met "$P2" >/dev/null
log_append lane.transition acceptance_met reviewing      "$P2" >/dev/null
log_append lane.transition reviewing      confirmed      "$P2" >/dev/null   # witnessless
verify_log_chain >/dev/null || fail "forge is still validly chained (the point)"
[ "$(project_state "$P2")" = corrupt ] || fail "FORGE SUCCEEDED: witnessless confirmed not rejected"
echo "PASS C: legal-chain witnessless confirmed → corrupt (premature-done blocked)"

# C2. DEEP forge: self-minted w3 artifact + full witness_evidence, but the
# referenced verdict_event hash was never appended → corrupt (MP1-TRUST-CORE).
P3=forge-deep
log_append lane.transition submitted     packeted       "$P3" >/dev/null
log_append lane.transition packeted       executing      "$P3" >/dev/null
log_append lane.transition executing      acceptance_met "$P3" >/dev/null
log_append lane.transition acceptance_met reviewing      "$P3" >/dev/null
printf '{"verdict":"pass"}\n' > "$SIFT_REVIEWS/$P3.w3.json"
fh=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$SIFT_REVIEWS/$P3.w3.json")
FORGE=$(python3 -c 'import json,sys;print(json.dumps({"verdict_event":"0"*64,"feature_sha":"x","extended_hash":"x","w1_ok":True,"w2_hash":"x","w3_hash":sys.argv[1],"w4_hash":"x"}))' "$fh")
log_append lane.transition reviewing confirmed "$P3" "$FORGE" >/dev/null
verify_log_chain >/dev/null || fail "deep forge is still validly chained (the point)"
[ "$(project_state "$P3")" = corrupt ] || fail "DEEP FORGE not rejected (self-minted artifact, no chained verdict event)"
echo "PASS C2: self-minted-artifact confirmed w/o chained verdict event → corrupt"

# C3. partially_confirmed must be witness-bound too — a forged partially_confirmed
# (bogus verdict_event not in-chain) must replay to corrupt, not partially_confirmed.
P4=forge-partial
log_append lane.transition submitted     packeted       "$P4" >/dev/null
log_append lane.transition packeted       executing      "$P4" >/dev/null
log_append lane.transition executing      acceptance_met "$P4" >/dev/null
log_append lane.transition acceptance_met reviewing      "$P4" >/dev/null
PFORGE=$(python3 -c 'import json;print(json.dumps({"verdict_event":"0"*64,"feature_sha":"x","extended_hash":"x","w1_ok":True,"w2_hash":"x","w3_hash":"x","w4_hash":"x"}))')
log_append lane.transition reviewing partially_confirmed "$P4" "$PFORGE" >/dev/null
[ "$(project_state "$P4")" = corrupt ] || fail "FORGE SUCCEEDED: witnessless partially_confirmed not rejected"
echo "PASS C3: witnessless partially_confirmed → corrupt (soft-floor state can't be forged)"

# D. tamper a committed line → chain breaks
python3 - "$SIFT_LOG" <<'PY'
import sys
p=sys.argv[1]; ls=open(p).read().splitlines()
ls[0]=ls[0].replace('"toy-001"','"toy-XXX"',1)
open(p,"w").write("\n".join(ls)+"\n")
PY
if verify_log_chain >/dev/null 2>&1; then fail "tampered log must fail chain verification"; fi
echo "PASS D: tampered committed line → chain verification fails (tamper-evident)"

echo "ALL TRUST-CORE ASSERTIONS PASS"
