#!/usr/bin/env bash
# Acceptance for AUDIT-PROVENANCE. RED on HEAD: _audit.py never reads the W2 mode, so a
# fresh_clone_unavailable (or feature_sha=nogit) confirmed audits as an indistinguishable
# clean PASS. GREEN: audit prints w2_mode and labels a degraded reproduce PASS(degraded).
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS 2>/dev/null || true
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export SIFT_REPO_ROOT="$W" SIFT_LOG="$W/.harness/log.jsonl" SIFT_REVIEWS="$W/.harness/reviews"
mkdir -p "$SIFT_REVIEWS"; . "$ROOT/kernel/log.sh"; . "$ROOT/kernel/state.sh"
_sha(){ python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# build a genuine witness-bound confirmed for $1 whose w2.json carries mode=$2 and
# feature_sha=$3, so audit has a real terminal to grade.
mkconfirmed(){ local P="$1" MODE="$2" FS="$3"
  printf '{"verdict":"pass","confidence":0.9}\n'              > "$SIFT_REVIEWS/$P.w3.json"
  printf '{"w2":"reproduced","mode":"%s"}\n' "$MODE"          > "$SIFT_REVIEWS/$P.w2.json"
  printf '{"ok":true}\n'                                       > "$SIFT_REVIEWS/$P.w4.json"
  printf 'pkt %s\n' "$P"                                       > "$SIFT_REVIEWS/$P.packet"
  local h2 h3 h4 eh; h2=$(_sha "$SIFT_REVIEWS/$P.w2.json"); h3=$(_sha "$SIFT_REVIEWS/$P.w3.json")
  h4=$(_sha "$SIFT_REVIEWS/$P.w4.json"); eh=$(_sha "$SIFT_REVIEWS/$P.packet")
  for e in "submitted packeted" "packeted executing" "executing acceptance_met" "acceptance_met reviewing"; do
    set -- $e; log_append lane.transition "$1" "$2" "$P" >/dev/null; done
  local vj veh we
  vj="$(python3 -c 'import json,sys;print(json.dumps({"verdict":"pass","feature_sha":sys.argv[4],"w2_hash":sys.argv[1],"w3_hash":sys.argv[2],"w4_hash":sys.argv[3]}))' "$h2" "$h3" "$h4" "$FS")"
  veh="$(log_append review.verdict reviewing reviewing "$P" "$vj")"
  we="$(python3 -c 'import json,sys;print(json.dumps({"verdict_event":sys.argv[1],"feature_sha":sys.argv[6],"extended_hash":sys.argv[5],"w1_ok":True,"w2_hash":sys.argv[2],"w3_hash":sys.argv[3],"w4_hash":sys.argv[4]}))' "$veh" "$h2" "$h3" "$h4" "$eh" "$FS")"
  log_append lane.transition reviewing confirmed "$P" "$we" >/dev/null
}

# 1. a DEGRADED (fresh_clone_unavailable) confirmed: audit must surface the mode AND mark it degraded.
mkconfirmed degr fresh_clone_unavailable abc
[ "$(SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" state degr 2>/dev/null)" = confirmed ] || fail "scaffold: degr not confirmed"
out="$(SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" audit degr 2>&1 || true)"
printf '%s' "$out" | grep -qiE 'w2_mode|w2 mode|reproduce mode' \
  || fail "audit did not surface the W2 reproduce mode (RED: _audit.py never reads <id>.w2.json mode)"
printf '%s' "$out" | grep -qiE 'degraded|fresh_clone_unavailable|soft.?floor' \
  || fail "audit did not label a fresh_clone_unavailable confirmed as degraded (RED: soft floor invisible to the second party)"

# 2. a CLEAN_CHECKOUT confirmed: audit prints clean_checkout and a plain (non-degraded) PASS.
mkconfirmed clean clean_checkout abc
out2="$(SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" audit clean 2>&1 || true)"
printf '%s' "$out2" | grep -qiE 'clean_checkout' \
  || fail "audit did not surface w2_mode clean_checkout for a clean confirmed"
printf '%s' "$out2" | grep -qiE 'degraded' \
  && fail "audit labeled a clean_checkout confirmed as degraded (false degrade)"

# 3. a feature_sha=="nogit" confirmed is labeled degraded (no resolvable provenance).
mkconfirmed nog clean_checkout nogit
out3="$(SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" audit nog 2>&1 || true)"
printf '%s' "$out3" | grep -qiE 'degraded|nogit|no.?git|unresolved' \
  || fail "audit did not flag a feature_sha=nogit confirmed as degraded/unresolved provenance"

echo "PASS: audit surfaces the W2 reproduce mode and labels a fresh_clone_unavailable / nogit confirmed PASS(degraded), while a clean_checkout confirmed stays a plain PASS"
