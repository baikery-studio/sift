#!/usr/bin/env bash
# selftest: regression coverage for the trust-core durability + verb additions that
# shipped untested (UP-6 migrate-log, UP-7 torn-line repair + abort, UP-9 audit). This
# suite is globbed into the selftest sweep, so these paths are covered on every run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIFT="$ROOT/bin/sift"; LOGPY="$ROOT/kernel/_log.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS 2>/dev/null || true

# --- migrate-log ---------------------------------------------------------------
OLD="$W/old.jsonl"
printf '{"event_id":"a","kind":"lane.transition","lane":"packeted","metadata":{"from":"submitted","to":"packeted"},"packet_id":"m"}\n' > "$OLD"
python3 "$LOGPY" verify "$OLD" >/dev/null 2>&1 && fail "all-old log should not verify clean"
python3 "$LOGPY" migrate "$OLD" >/dev/null 2>&1 || fail "migrate refused a genuine all-old-schema log"
python3 "$LOGPY" verify "$OLD" >/dev/null 2>&1 || fail "migrated log does not verify clean"
out="$(python3 "$LOGPY" migrate "$OLD" 2>&1 || true)"
printf '%s' "$out" | grep -qi 'already current\|nothing to migrate' || fail "re-migrate of a current log is not a no-op (got: $out)"
# mixed (tampered) log must be refused
MIX="$W/mix.jsonl"
SIFT_KIND=lane.transition SIFT_PACKET=m SIFT_FROM=a SIFT_TO=b python3 "$LOGPY" append "$MIX" >/dev/null
printf '{"event_id":"x","kind":"lane.transition","packet_id":"m"}\n' >> "$MIX"   # a no-hash line in a chained log
set +e; python3 "$LOGPY" migrate "$MIX" >/dev/null 2>&1; mrc=$?; set -e
[ "$mrc" != 0 ] || fail "migrate accepted a MIXED log (laundering path)"

# --- torn-line repair ----------------------------------------------------------
. "$ROOT/kernel/log.sh"
TL="$W/torn"; export SIFT_LOG="$TL/log.jsonl"; mkdir -p "$TL"
log_append lane.transition submitted packeted P1 >/dev/null
printf '{"seq":2,"kind":"lane.tr' >> "$SIFT_LOG"          # torn partial last line
log_append lane.transition packeted executing P1 >/dev/null 2>&1 || fail "append bricked by a torn last line (no repair)"
verify_log_chain >/dev/null 2>&1 || fail "chain did not re-verify after torn-line repair"
unset SIFT_LOG

# --- abort ---------------------------------------------------------------------
AB="$W/abort"; mkdir -p "$AB/tasks/packets" "$AB/out"
( cd "$AB"; SIFT_REPO_ROOT="$AB" "$SIFT" setup >/dev/null 2>&1 )
cat > "$AB/tasks/packets/ab.md" <<'EOF'
---
id: ab
profile: toy
goal: produce a greeting artifact that carries the marker
artifact:
  path: out/ab.txt
  marker: HELLO-SIFT
---
EOF
printf 'a greeting\nHELLO-SIFT\n' > "$AB/out/ab.txt"
SIFT_REPO_ROOT="$AB" "$SIFT" plan ab >/dev/null 2>&1 || fail "abort fixture: plan failed"
SIFT_REPO_ROOT="$AB" "$SIFT" execute ab >/dev/null 2>&1 || fail "abort fixture: execute failed"
# force into reviewing by hand-driving the legal transition, then abort
( cd "$AB"; SIFT_REPO_ROOT="$AB" SIFT_LOG="$AB/.harness/log.jsonl" bash -c '. '"$ROOT"'/kernel/log.sh; log_append lane.transition acceptance_met reviewing ab >/dev/null' )
SIFT_REPO_ROOT="$AB" "$SIFT" abort ab >/dev/null 2>&1 || fail "sift abort failed on a reviewing packet"
st="$(SIFT_REPO_ROOT="$AB" "$SIFT" state ab)"
[ "$st" = review_failed ] || fail "abort did not move reviewing -> review_failed (got $st, must replay legal not corrupt)"
# a non-abortable state is rejected
SIFT_REPO_ROOT="$AB" "$SIFT" abort ab >/dev/null 2>&1 && fail "abort accepted a non-abortable (review_failed) state"

# --- audit ---------------------------------------------------------------------
AU="$W/audit"; export SIFT_REPO_ROOT="$AU" SIFT_LOG="$AU/.harness/log.jsonl" SIFT_REVIEWS="$AU/.harness/reviews"
mkdir -p "$SIFT_REVIEWS"; . "$ROOT/kernel/state.sh"
sha(){ python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
P=g
printf '{"verdict":"pass"}\n' > "$SIFT_REVIEWS/$P.w3.json"; printf '{"w2":"x"}\n' > "$SIFT_REVIEWS/$P.w2.json"
printf '{"ok":true}\n' > "$SIFT_REVIEWS/$P.w4.json"; printf 'pkt\n' > "$SIFT_REVIEWS/$P.packet"
h2=$(sha "$SIFT_REVIEWS/$P.w2.json"); h3=$(sha "$SIFT_REVIEWS/$P.w3.json"); h4=$(sha "$SIFT_REVIEWS/$P.w4.json"); eh=$(sha "$SIFT_REVIEWS/$P.packet")
for e in "submitted packeted" "packeted executing" "executing acceptance_met" "acceptance_met reviewing"; do set -- $e; log_append lane.transition "$1" "$2" "$P" >/dev/null; done
vj="$(python3 -c 'import json,sys;print(json.dumps({"verdict":"pass","feature_sha":"abc","w2_hash":sys.argv[1],"w3_hash":sys.argv[2],"w4_hash":sys.argv[3]}))' "$h2" "$h3" "$h4")"
veh="$(log_append review.verdict reviewing reviewing "$P" "$vj")"
we="$(python3 -c 'import json,sys;print(json.dumps({"verdict_event":sys.argv[1],"feature_sha":"abc","extended_hash":sys.argv[5],"w1_ok":True,"w2_hash":sys.argv[2],"w3_hash":sys.argv[3],"w4_hash":sys.argv[4]}))' "$veh" "$h2" "$h3" "$h4" "$eh")"
log_append lane.transition reviewing confirmed "$P" "$we" >/dev/null
SIFT_REPO_ROOT="$AU" "$SIFT" audit "$P" >/dev/null 2>&1 || fail "audit FAILED a genuine confirmed"
log_append lane.transition submitted packeted bad >/dev/null
for e in "packeted executing" "executing acceptance_met" "acceptance_met reviewing" "reviewing confirmed"; do set -- $e; log_append lane.transition "$1" "$2" bad >/dev/null; done
SIFT_REPO_ROOT="$AU" "$SIFT" audit bad >/dev/null 2>&1 && fail "audit PASSED a witnessless forge"

echo "PASS: migrate-log (clean/noop/refuse-mixed) + torn-line repair + abort edge + audit pass/fail"
