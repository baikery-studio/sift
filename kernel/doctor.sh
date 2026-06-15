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
  # A witness-bound terminal is {confirmed, partially_confirmed} — both carry bound W2/W3/W4
  # artifacts that must still re-verify, so doctor scans both (a partially_confirmed with a
  # silently-deleted artifact is the same silent-degradation case as a confirmed one).
  local ever_confirmed id problems=0
  ever_confirmed="$(python3 -c 'import json,sys
ids=set()
for l in open(sys.argv[1]):
    if not l.strip(): continue
    try: e=json.loads(l)
    except Exception: continue
    if e.get("kind")=="lane.transition" and e.get("to") in ("confirmed","partially_confirmed"):
        ids.add(e.get("packet_id"))
print("\n".join(sorted(i for i in ids if i)))' "$SIFT_LOG")"
  # SCALE-MEMO: resolve every ever-confirmed packet's state in ONE batch call (the chain is
  # verified ONCE, not once per id), so doctor over a long log is O(N+P), not O(P×N). The
  # per-id artifact re-hash below reads the log but never re-verifies the chain.
  local _states; _states="$(project_states_batch $ever_confirmed 2>/dev/null)"
  _state_of(){ printf '%s\n' "$_states" | awk -v i="$1" -F'\t' '$1==i{print $2; exit}'; }
  # The non-superseded ever-confirmed set (superseded packets may have had artifacts cleaned up).
  local _check_ids; _check_ids="$(printf '%s\n' "$_states" | awk -F'	' '$2!="superseded"{print $1}')"
  # RE-VERIFY, don't just check existence, but read the log ONCE for ALL packets (not once per
  # id — that per-id full-log read was the remaining O(P×N) factor). Recompute sha256 of each
  # bound witness artifact and compare to the hash in the terminal event: a deleted artifact is
  # MISSING, a content-swapped one is TAMPERED. Emits "<pid>\t<MISSING|TAMPERED>\t<suffix>".
  local _probout
  _probout="$(SIFT_DOC_IDS="$_check_ids" python3 -c '
import json, sys, os, hashlib
log, reviews = sys.argv[1], sys.argv[2]
ids = set(os.environ.get("SIFT_DOC_IDS", "").split())
we_by = {}
for l in open(log):
    if not l.strip():
        continue
    try:
        e = json.loads(l)
    except Exception:
        continue
    if e.get("kind") == "lane.transition" and e.get("to") in ("confirmed","partially_confirmed") and e.get("packet_id") in ids:
        we_by[e.get("packet_id")] = e.get("witness_evidence") or {}   # last terminal wins
probs = 0
for pid, we in we_by.items():
    for wk, suf in (("w2_hash", ".w2.json"), ("w3_hash", ".w3.json"), ("w4_hash", ".w4.json")):
        bound = we.get(wk)
        if not bound:
            continue   # pre-binding terminal without this hash — nothing to re-verify
        art = os.path.join(reviews, pid + suf)
        if not os.path.exists(art):
            print("%s\tMISSING\t%s" % (pid, suf)); probs += 1
        elif hashlib.sha256(open(art, "rb").read()).hexdigest() != bound:
            print("%s\tTAMPERED\t%s" % (pid, suf)); probs += 1
sys.exit(1 if probs else 0)
' "$SIFT_LOG" "$SIFT_REVIEWS" 2>/dev/null)" || true
  while IFS="	" read -r _pid _kind _suf; do
    [ -n "$_pid" ] || continue
    echo "[doctor] $_kind witness artifact for witness-bound terminal '$_pid' ($_suf): re-verification failed (bound hash mismatch)" >&2
    problems=$((problems+1))
  done <<EOF
$_probout
EOF
  if [ "$problems" -gt 0 ]; then echo "[doctor] $problems problem(s) found" >&2; return 1; fi
  echo "[doctor] ok — every confirmed packet re-verifies (artifacts present and hash-matched)"
}
