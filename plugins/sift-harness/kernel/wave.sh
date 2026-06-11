#!/usr/bin/env bash
# kernel/wave.sh — W5 system-level wave-review (self-hosted). After every member
# of a declared wave reaches `confirmed`, prove the wave as a WHOLE is:
#   R1 wired      — each member's W4 reachability holds (cross-packet)
#   R2 covered    — sift selftest green + no coverage orphan
#   R3 e2e-tested — the declared end-to-end path runs green
#   R5 no-dormant — no function in a touched file is defined-but-unreferenced
# (R4 coherence is demonstrated by R2+R3 running the composed pieces together.)
# All pass -> gate the wave to `shipped`. Fail-closed.
_WAVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_WAVE_DIR/config.sh"; . "$_WAVE_DIR/state.sh"; . "$_WAVE_DIR/packet.sh"
SIFT_PACKETS="${SIFT_PACKETS:-$(config_path packets)}"
SIFT_STATE="${SIFT_STATE:-$(config_path state)}"

# sift_coverage <wid> — ADVISORY wave gap-finding (UP-11). Checks each goal_requirement
# maps to at least one member packet (by distinctive-token overlap with its goal/objective)
# and reports UNCOVERED requirements. NEVER mutates the plan — gap-finding, not adaptive
# control, so the spine's plan immutability is preserved. Always exits 0 (advisory).
sift_coverage() {
  local wid="${1:-}"; [ -n "$wid" ] || { echo "[sift] usage: sift coverage <wave>" >&2; return 1; }
  local plug="${SIFT_PLUGIN_ROOT:-$(cd "$_WAVE_DIR/.." && pwd)}"
  local reporoot="${SIFT_REPO_ROOT:-$(pwd)}"
  local man="$reporoot/tasks/waves/$wid.json"; [ -f "$man" ] || man="$plug/tasks/waves/$wid.json"
  [ -f "$man" ] || { echo "[coverage] no wave manifest: $wid" >&2; return 1; }
  local members m texts=""
  members="$(python3 -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1])).get("members",[])))' "$man")"
  for m in $members; do
    texts="$texts $(packet_field "$m" goal 2>/dev/null) $(packet_field "$m" objective 2>/dev/null)"
  done
  SIFT_WAVE_MEMBER_TEXT="$texts" python3 -c '
import json,os,re,sys
man=json.load(open(sys.argv[1])); reqs=man.get("goal_requirements",[])
text=os.environ.get("SIFT_WAVE_MEMBER_TEXT","").lower()
STOP=set("the a an of to is are returns return exists exist and or for with that this in on at it its".split())
if not reqs:
    print("[coverage] %s: no goal_requirements declared (nothing to check)" % man.get("id","?")); sys.exit(0)
uncovered=[]
for r in reqs:
    toks=[t for t in re.findall(r"[a-z0-9]+", r.lower()) if len(t)>=4 and t not in STOP]
    if toks and sum(1 for t in toks if t in text) < max(1,(len(toks)+1)//2):
        uncovered.append(r)
if uncovered:
    print("[coverage] %s: %d/%d goal_requirements UNCOVERED by any member packet (advisory):" % (man.get("id"),len(uncovered),len(reqs)))
    for u in uncovered: print("    UNCOVERED: %s" % u)
    print("[coverage] advisory only — emit packets to cover these or accept the gap; the plan is NOT mutated.")
else:
    print("[coverage] %s: all %d goal_requirements covered by a member packet." % (man.get("id"),len(reqs)))
' "$man"
}

sift_wave_review() {
  if [ -n "${SIFT_IN_WAVE:-}" ]; then echo "  (nested wave-review skipped)"; return 0; fi
  export SIFT_IN_WAVE=1
  local wid="$1"
  local plug="${SIFT_PLUGIN_ROOT:-$(cd "$_WAVE_DIR/.." && pwd)}"
  local reporoot="${SIFT_REPO_ROOT:-$(pwd)}"
  local man="$reporoot/tasks/waves/$wid.json"; [ -f "$man" ] || man="$plug/tasks/waves/$wid.json"
  [ -f "$man" ] || { echo "[w5] no wave manifest: $wid" >&2; return 1; }
  local members touched e2e
  members="$(python3 -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1]))["members"]))' "$man")"
  touched="$(python3 -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1])).get("touched_files",[])))' "$man")"
  e2e="$(python3 -c 'import json,sys;print(" ".join(json.load(open(sys.argv[1])).get("e2e",[])))' "$man")"

  # gate_ready: every member confirmed
  local m
  for m in $members; do
    [ "$(project_state "$m")" = confirmed ] || { echo "[w5] not gate_ready: $m is $(project_state "$m")" >&2; return 1; }
  done
  # R1 cross-packet wiring — resolve each member's W4 from ITS OWN profile.
  local prof w4
  for m in $members; do
    prof="$(packet_field "$m" profile)"
    w4="$plug/profiles/$prof/witness_w4.sh"
    [ -f "$w4" ] || { echo "[w5] R1 no W4 witness for profile '$prof' (member $m)" >&2; return 1; }
    bash "$w4" "$SIFT_PACKETS/$m.md" "$m" >/dev/null 2>&1 \
      || { echo "[w5] R1 wiring FAIL: $m" >&2; return 1; }
  done
  # R2 coverage / selftest
  ( . "$plug/kernel/selftest.sh"; sift_selftest >/dev/null 2>&1 ) || { echo "[w5] R2 coverage/selftest FAIL" >&2; return 1; }
  # R3 e2e
  for t in $e2e; do bash "$plug/$t" >/dev/null 2>&1 || { echo "[w5] R3 e2e FAIL: $t" >&2; return 1; }; done
  # R5 dormant-hunt
  local dz; dz="$(python3 "$plug/kernel/_wave_dormant.py" "$plug" $touched)"
  [ -z "$dz" ] || { echo "[w5] R5 DORMANT (defined, never called outside its file):" >&2; printf '    %s\n' $dz >&2; return 1; }
  # SHIP — JSON-escape wave id + members so the verdict record is always valid JSON
  mkdir -p "$reporoot/.harness/waves"
  python3 -c 'import json,sys
print(json.dumps({"wave":sys.argv[1],"verdict":"shipped","R1":"ok","R2":"ok","R3":"ok","R5":"ok","members":sys.argv[2]}))' \
    "$wid" "$members" > "$reporoot/.harness/waves/$wid.json"
  echo "[w5] $wid SHIPPED — R1 wired · R2 covered · R3 e2e · R5 no-dormant"
}
