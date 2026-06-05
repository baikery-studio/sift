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
    if [ ! -f "$SIFT_REVIEWS/$id.w3.json" ]; then
      echo "[doctor] MISSING load-bearing W3 artifact for confirmed packet '$id' ($SIFT_REVIEWS/$id.w3.json) — packet now replays as corrupt" >&2
      problems=$((problems+1))
    fi
  done
  if [ "$problems" -gt 0 ]; then echo "[doctor] $problems problem(s) found" >&2; return 1; fi
  echo "[doctor] ok — every confirmed packet still has its W3 artifact"
}
