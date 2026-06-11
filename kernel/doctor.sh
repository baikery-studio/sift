#!/usr/bin/env bash
# kernel/doctor.sh — read-only health check. Surfaces the silent-degradation case
# from the MP1 review: a packet that REACHED a `confirmed` event in the log but
# whose load-bearing W3 artifact (.harness/reviews/<id>.w3.json) is now missing.
# Without this, project_state just reports `corrupt` with no hint that the cause
# is a deleted artifact rather than real tampering. Exit 1 if any problem found.
_DOC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_DOC_DIR/config.sh"; . "$_DOC_DIR/state.sh"
SIFT_LOG="${SIFT_LOG:-$(config_path log)}"
SIFT_REVIEWS="${SIFT_REVIEWS:-$(config_path reviews)}"

sift_doctor() {
  # FORT-4 weak-acceptance scan (runs even before any log exists): flag any packet whose
  # acceptance script is still the unwritten scaffold stub (sentinel "TODO: assert ...
  # acceptance criteria"). Advisory nudge — a hollow test cannot back a trusted confirmed.
  local _snaps _weak=0 _t _pid
  _snaps="$(config_path snapshots 2>/dev/null || echo "$SIFT_REPO_ROOT/evals/snapshots")"
  if [ -d "$_snaps" ]; then
    for _t in "$_snaps"/*/test.sh; do
      [ -f "$_t" ] || continue
      if grep -qE 'TODO: assert .* acceptance criteria' "$_t"; then
        _pid="$(basename "$(dirname "$_t")")"
        echo "[doctor] WEAK ACCEPTANCE: packet '$_pid' still has the unwritten placeholder stub ($_t) — replace it with a real test before trusting confirmed" >&2
        _weak=$((_weak+1))
      fi
    done
  fi
  [ "$_weak" -gt 0 ] && echo "[doctor] $_weak weak-acceptance warning(s) (advisory)" >&2

  [ -f "$SIFT_LOG" ] || { echo "[doctor] no log at $SIFT_LOG — nothing to check"; return 0; }
  local ever_confirmed id problems=0
  ever_confirmed="$(python3 -c 'import json,sys
ids=set()
for l in open(sys.argv[1]):
    if not l.strip(): continue
    try: e=json.loads(l)
    except Exception: continue
    if e.get("kind")=="lane.transition" and e.get("to")=="confirmed":
        ids.add(e.get("packet_id"))
print("\n".join(sorted(i for i in ids if i)))' "$SIFT_LOG")"
  for id in $ever_confirmed; do
    # a packet legitimately retired after confirm (superseded) may have had its
    # artifact cleaned up — not a problem, skip it.
    [ "$(project_state "$id")" = superseded ] && continue
    # RE-VERIFY, don't just check existence: recompute sha256 of each bound witness
    # artifact and compare to the hash recorded in the confirmed event. A deleted
    # artifact is MISSING; a content-swapped one is TAMPERED. A one-shot pass that
    # only checked existence let a silently-mutated W3 artifact still read "ok".
    local _res
    _res="$(python3 -c '
import json, sys, os, hashlib
log, reviews, pid = sys.argv[1], sys.argv[2], sys.argv[3]
we = None
for l in open(log):
    if not l.strip():
        continue
    try:
        e = json.loads(l)
    except Exception:
        continue
    if e.get("kind") == "lane.transition" and e.get("to") == "confirmed" and e.get("packet_id") == pid:
        we = e.get("witness_evidence") or {}
probs = []
if we is not None:
    for wk, suf in (("w2_hash", ".w2.json"), ("w3_hash", ".w3.json"), ("w4_hash", ".w4.json")):
        bound = we.get(wk)
        if not bound:
            continue   # pre-binding confirmed without this hash — nothing to re-verify
        art = os.path.join(reviews, pid + suf)
        if not os.path.exists(art):
            probs.append("MISSING " + suf)
        elif hashlib.sha256(open(art, "rb").read()).hexdigest() != bound:
            probs.append("TAMPERED " + suf)
for p in probs:
    print(p)
sys.exit(1 if probs else 0)
' "$SIFT_LOG" "$SIFT_REVIEWS" "$id" 2>/dev/null)" || {
      while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        echo "[doctor] ${_line%% *} witness artifact for confirmed packet '$id' (${_line#* }) — re-verification failed (bound hash mismatch)" >&2
        problems=$((problems+1))
      done <<EOF
$_res
EOF
    }
  done
  if [ "$problems" -gt 0 ]; then echo "[doctor] $problems problem(s) found" >&2; return 1; fi
  echo "[doctor] ok — every confirmed packet re-verifies (artifacts present and hash-matched)"
}
