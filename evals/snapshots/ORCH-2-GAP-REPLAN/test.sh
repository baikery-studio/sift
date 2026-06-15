#!/usr/bin/env bash
# Acceptance for ORCH-2-GAP-REPLAN. RED on HEAD: there is NO append-only coverage-fed
# replan step. kernel/wave.sh sift_coverage (~19-49) is ADVISORY ONLY — it prints UNCOVERED
# requirements and exits 0, NEVER mutating anything. No code path turns an UNCOVERED
# goal_requirement into a scaffolded covering packet + a manifest members-append + a chained
# 'packet.emit' event. 'sift drive' does not exist (bin/sift ~39 fail-soft no-op).
#
# The GREEN target (kernel/drive.sh, driven later) reads sift_coverage's UNCOVERED list and,
# for each gap, calls sift_scaffold + appends the new id to tasks/waves/<wid>.json members +
# log_append packet.emit (chained, INERT to state projection: _state.py replays only
# kind=='lane.transition' and binds only kind=='review.verdict', so packet.emit is verifiable
# but moves no state). Coverage stays ADVISORY.
#
# Behavioral RED (sift drive is fail-soft so we assert EFFECTS, not exit code):
#   (a) a NEW member packet was scaffolded (tasks/packets/<new>.md + evals/snapshots/<new>/test.sh)
#   (b) the manifest members[] grew to include it
#   (c) a chained 'packet.emit' event was logged AND verify-log still passes
# GUARD (no false-green / no over-broad mutation): a wave whose requirements are ALL covered
#   scaffolds NOTHING, appends NOTHING, and emits NO packet.emit.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS SIFT_SNAPSHOTS 2>/dev/null || true

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/tasks/waves" "$W/tasks/packets" "$W/evals/snapshots" "$W/.harness/reviews"
export SIFT_REPO_ROOT="$W" \
       SIFT_LOG="$W/.harness/log.jsonl" \
       SIFT_REVIEWS="$W/.harness/reviews" \
       SIFT_PACKETS="$W/tasks/packets" \
       SIFT_SNAPSHOTS="$W/evals/snapshots"

# count members[] in a manifest, and count distinct packet.emit events for a wave scope.
members_count(){ python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("members",[])))' "$1"; }
emit_count(){ python3 -c '
import json,sys
n=0
try:
    for ln in open(sys.argv[1]):
        ln=ln.strip()
        if not ln: continue
        try: e=json.loads(ln)
        except Exception: continue
        if e.get("kind")=="packet.emit": n+=1
except FileNotFoundError:
    pass
print(n)' "${1:-$SIFT_LOG}"; }

# ---- GAP wave: one goal_requirement that NO member covers (distinctive tokens absent). ----
cat > "$W/tasks/waves/gapwave.json" <<'JSON'
{
  "id": "gapwave",
  "members": ["COVERED-MEMBER"],
  "goal_requirements": [
    "the orchestrator exposes a quarantine verb that isolates poisoned narrative fragments"
  ]
}
JSON
# the existing member is about something ELSE — its goal/objective share no distinctive
# tokens with the requirement, so sift_coverage reports the requirement UNCOVERED.
cat > "$SIFT_PACKETS/COVERED-MEMBER.md" <<'MD'
---
id: COVERED-MEMBER
profile: software
goal: render the dashboard sidebar with collapsible navigation groups
objective: |
  builds the left-hand navigation panel and its keyboard shortcuts
---
MD

# SANITY: confirm HEAD's sift_coverage DOES see this requirement as UNCOVERED (so the gap the
# replan must close genuinely exists; a scaffold bug that mis-covers would hide the RED).
covout="$(SIFT_REPO_ROOT="$W" SIFT_PACKETS="$SIFT_PACKETS" bash "$ROOT/bin/sift" coverage gapwave 2>/dev/null)"
printf '%s' "$covout" | grep -q 'UNCOVERED: the orchestrator exposes a quarantine verb' \
  || fail "scaffold broken: sift_coverage did not report the planted requirement as UNCOVERED (it said: $covout)"

# snapshot the pre-state so the GUARD wave can be compared and the RED effects are unambiguous.
before_members="$(members_count "$W/tasks/waves/gapwave.json")"
before_emits="$(emit_count)"
before_pkts="$(ls "$SIFT_PACKETS" | wc -l | tr -d ' ')"

# ---- INVOKE the (new) gap-fed replan step. fail-soft today => no effect on HEAD. -----------
# Drives the wave: read coverage, scaffold a covering packet per UNCOVERED requirement, append
# it to members, emit a chained packet.emit. On HEAD 'sift drive' is an unknown subcommand.
SIFT_REPO_ROOT="$W" SIFT_PACKETS="$SIFT_PACKETS" SIFT_SNAPSHOTS="$SIFT_SNAPSHOTS" \
  bash "$ROOT/bin/sift" drive gapwave >/dev/null 2>&1 || true

# ---- (a) a NEW covering packet was scaffolded (packet + snapshot test). --------------------
after_pkts="$(ls "$SIFT_PACKETS" | wc -l | tr -d ' ')"
[ "$after_pkts" -gt "$before_pkts" ] \
  || fail "no covering packet was scaffolded for the UNCOVERED requirement (RED: coverage is advisory-only; there is no scaffold-on-gap path in kernel/drive.sh)"
# the new packet id is whatever member is in the manifest but not the original — find it and
# assert BOTH artifacts exist (sift_scaffold writes packet + snapshot test).
newid="$(python3 -c '
import json,sys
m=json.load(open(sys.argv[1])).get("members",[])
orig={"COVERED-MEMBER"}
extra=[x for x in m if x not in orig]
print(extra[0] if extra else "")' "$W/tasks/waves/gapwave.json")"
[ -n "$newid" ] \
  || fail "manifest members[] did not grow with a new covering packet (RED: no manifest-append on gap)"
[ -f "$SIFT_PACKETS/$newid.md" ] \
  || fail "scaffolded member '$newid' has no packet file tasks/packets/$newid.md (RED)"
[ -f "$SIFT_SNAPSHOTS/$newid/test.sh" ] \
  || fail "scaffolded member '$newid' has no acceptance test evals/snapshots/$newid/test.sh (RED)"

# ---- (b) the manifest members[] grew to include the new covering packet. -------------------
after_members="$(members_count "$W/tasks/waves/gapwave.json")"
[ "$after_members" -gt "$before_members" ] \
  || fail "manifest members[] count did not grow (RED: gap requirement was not appended as a member)"

# ---- (c) a chained packet.emit was logged AND the chain still verifies. --------------------
after_emits="$(emit_count)"
[ "$after_emits" -gt "$before_emits" ] \
  || fail "no chained 'packet.emit' event was logged for the emitted covering packet (RED: no log_append packet.emit on gap)"
SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" verify-log >/dev/null 2>&1 \
  || fail "the log chain does not verify after the replan emit (CORE-SAFETY: packet.emit must be appended as a chained event, never a raw write)"

# ---- (d) the scaffolded packet actually CLOSES the gap (not just ANY packet). ---------------
# Re-run coverage: the requirement that was UNCOVERED must now be covered by the new member.
# Defeats a cheat that scaffolds a random/empty packet to satisfy (a)-(c) without covering.
cov_after="$(SIFT_REPO_ROOT="$W" SIFT_PACKETS="$SIFT_PACKETS" bash "$ROOT/bin/sift" coverage gapwave 2>/dev/null)"
printf '%s' "$cov_after" | grep -q 'UNCOVERED: the orchestrator exposes a quarantine verb' \
  && fail "the scaffolded packet did NOT close the gap — coverage still reports the requirement UNCOVERED (RED: replan must scaffold a packet whose goal/objective COVERS the requirement, not merely append any packet)"

# ---- GUARD: an ALL-COVERED wave scaffolds NOTHING / appends NOTHING / emits NOTHING. -------
# Fresh log + fresh manifest whose single requirement IS covered by its member's goal tokens.
rm -f "$SIFT_LOG"
cat > "$W/tasks/waves/fullwave.json" <<'JSON'
{
  "id": "fullwave",
  "members": ["QUARANTINE-MEMBER"],
  "goal_requirements": [
    "the orchestrator exposes a quarantine verb that isolates poisoned narrative fragments"
  ]
}
JSON
cat > "$SIFT_PACKETS/QUARANTINE-MEMBER.md" <<'MD'
---
id: QUARANTINE-MEMBER
profile: software
goal: orchestrator quarantine verb isolates poisoned narrative fragments
objective: |
  adds the quarantine verb so the orchestrator isolates poisoned narrative fragments
---
MD
g_covout="$(SIFT_REPO_ROOT="$W" SIFT_PACKETS="$SIFT_PACKETS" bash "$ROOT/bin/sift" coverage fullwave 2>/dev/null)"
printf '%s' "$g_covout" | grep -qi 'all .*covered' \
  || fail "guard precondition broken: sift_coverage did not report fullwave fully covered (said: $g_covout)"
g_before_members="$(members_count "$W/tasks/waves/fullwave.json")"
g_before_pkts="$(ls "$SIFT_PACKETS" | wc -l | tr -d ' ')"
g_before_emits="$(emit_count)"
SIFT_REPO_ROOT="$W" SIFT_PACKETS="$SIFT_PACKETS" SIFT_SNAPSHOTS="$SIFT_SNAPSHOTS" \
  bash "$ROOT/bin/sift" drive fullwave >/dev/null 2>&1 || true
[ "$(members_count "$W/tasks/waves/fullwave.json")" = "$g_before_members" ] \
  || fail "guard: an all-covered wave grew its members[] (spurious scaffold — replan must be gap-driven only)"
[ "$(ls "$SIFT_PACKETS" | wc -l | tr -d ' ')" = "$g_before_pkts" ] \
  || fail "guard: an all-covered wave scaffolded a packet (spurious — replan must be gap-driven only)"
[ "$(emit_count)" = "$g_before_emits" ] \
  || fail "guard: an all-covered wave emitted a packet.emit (spurious — replan must be gap-driven only)"

echo "PASS: gap-fed replan scaffolds a covering packet, appends it to the wave manifest, and logs a chained packet.emit; an all-covered wave is a no-op; coverage stays advisory; chain verifies"
