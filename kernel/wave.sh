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
