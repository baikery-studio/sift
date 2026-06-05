#!/usr/bin/env bash
# kernel/pipeline.sh — plan / execute / review driving a packet through the
# witnessed state machine. The terminal `confirmed` event embeds witness-evidence
# (W1..W4 hashes + feature_sha + extended_hash) so a witnessless `confirmed` is
# rejected by causal replay (_state.py). Profile witnesses are invoked as scripts
# (each self-invokes on direct exec). Sourced by bin/sift.
_PIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_PIPE_DIR/config.sh"; . "$_PIPE_DIR/packet.sh"; . "$_PIPE_DIR/log.sh"
. "$_PIPE_DIR/state.sh"; . "$_PIPE_DIR/lock.sh"; . "$_PIPE_DIR/manifest.sh"
SIFT_REVIEWS="${SIFT_REVIEWS:-$(config_path reviews)}"
SIFT_STATE="${SIFT_STATE:-$(config_path state)}"
# PLUGIN root holds kernel/ + profiles/ (where this file lives, ../).
# REPO root is the working repo (packets/state/artifacts), the operator's cwd.
SIFT_PLUGIN_ROOT="${SIFT_PLUGIN_ROOT:-$(cd "$_PIPE_DIR/.." && pwd)}"
SIFT_REPO_ROOT="${SIFT_REPO_ROOT:-$(pwd)}"
export SIFT_LOG SIFT_REVIEWS SIFT_STATE SIFT_PACKETS SIFT_REPO_ROOT SIFT_PLUGIN_ROOT

_sift_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
_json_true() { python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
sys.exit(0 if d.get(sys.argv[1]) else 1)' "$1"; }
# extract a human reason from a witness/acceptance JSON blob (for actionable errors)
_json_reason() { python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
e=d.get("evidence") if isinstance(d.get("evidence"),dict) else {}
print(d.get("reason") or e.get("error") or "")' 2>/dev/null || true; }
_prof_dir() { printf '%s/profiles/%s' "$SIFT_PLUGIN_ROOT" "$(packet_field "$1" profile)"; }

# BLOCKING pre-acceptance gate: scan the packet's acceptance/test files for
# test-tampering signatures (skip/xfail/continue-on-error/commented assert) the
# witness layer cannot see. Missing files are skipped by _signatures.py. A clean
# scan (or none applicable, e.g. bash acceptance) returns 0; a tamper hit returns 1.
_signatures_gate() {
  local _sg_id="$1" _sg_test
  local -a _sg_files
  # array, not a space-joined string, so a repo path containing spaces can't silently
  # mis-split the argument list and skip the scan (a false-negative bypass).
  _sg_files=("$SIFT_REPO_ROOT/evals/snapshots/$_sg_id/test.sh")
  _sg_test="$(packet_field "$_sg_id" test 2>/dev/null || true)"
  [ -n "$_sg_test" ] && [ -f "$SIFT_REPO_ROOT/$_sg_test" ] && _sg_files+=("$SIFT_REPO_ROOT/$_sg_test")
  python3 "$SIFT_PLUGIN_ROOT/kernel/_signatures.py" "${_sg_files[@]}"
}

sift_plan() {
  id="$1"; pf="$SIFT_PACKETS/$id.md"
  [ -f "$pf" ] || { echo "[sift] no packet: $id" >&2; return 1; }
  { [ -n "$(packet_field "$id" id)" ] && [ -n "$(packet_field "$id" profile)" ]; } || { echo "[sift] $id missing id/profile" >&2; return 1; }
  [ -d "$(_prof_dir "$id")" ] || { echo "[sift] $id: unknown profile" >&2; return 1; }
  # enforce the documented profile.json schema at load (fail closed on a bad manifest)
  _pv_json="$(_prof_dir "$id")/profile.json"
  if [ -f "$_pv_json" ]; then
    python3 "$SIFT_PLUGIN_ROOT/kernel/_profile_validate.py" "$_pv_json" \
      || { echo "[sift] $id: invalid profile.json — refusing to dispatch" >&2; return 1; }
  fi
  [ "$(project_state "$id")" = submitted ] || { echo "[sift] $id not 'submitted'" >&2; return 1; }
  log_append lane.transition submitted packeted "$id" >/dev/null
  mkdir -p "$SIFT_STATE"; printf '%s\n' "$id" > "$SIFT_STATE/focus"   # runtime scope guard: this is now the active packet
  rm -f "$SIFT_STATE/unpacketed-edit" 2>/dev/null || true             # FORT-1: agent engaged the loop — disarm the freehand-edit gate
  echo "[sift] planned $id (focus set; scope guard will fence edits to its scope.paths)"
}

sift_execute() {
  id="$1"; pf="$SIFT_PACKETS/$id.md"; pd="$(_prof_dir "$id")"
  sift_lock_acquire "$id" || { echo "[sift] dispatch locked (WIP=1)" >&2; return 1; }
  trap 'sift_lock_release' RETURN
  rm -f "$SIFT_STATE/dirty.$id" 2>/dev/null || true   # HERD-3: re-execution clears the stale-acceptance marker
  cur="$(project_state "$id")"
  case "$cur" in
    packeted)      log_append lane.transition packeted executing "$id" >/dev/null ;;
    failed)        log_append lane.transition failed executing "$id" >/dev/null ;;       # re-execute after a failed run
    review_failed) log_append lane.transition review_failed executing "$id" >/dev/null ;; # re-execute after a rejected review
    *) echo "[sift] $id not re-executable from '$cur'" >&2; return 1 ;;
  esac
  manifest_write "$id" >/dev/null 2>&1 || true   # pin run provenance (base/feature_sha)
  if ! _signatures_gate "$id" 2>>"$SIFT_STATE/signatures.log"; then
    log_append lane.transition executing failed "$id" >/dev/null
    echo "[sift] test-tampering signature in $id — blocked before acceptance (see signatures.log)" >&2; return 1
  fi
  local accout; accout="$(bash "$pd/acceptance/run.sh" "$pf" "$id" 2>/dev/null || true)"
  if printf '%s' "$accout" | _json_true passed; then
    log_append lane.transition executing acceptance_met "$id" >/dev/null; echo "[sift] acceptance_met $id"
  else
    log_append lane.transition executing failed "$id" >/dev/null
    echo "[sift] acceptance FAILED $id: $(printf '%s' "$accout" | _json_reason)" >&2; return 1
  fi
}

sift_review() {
  id="$1"; pf="$SIFT_PACKETS/$id.md"; pd="$(_prof_dir "$id")"
  [ "$(project_state "$id")" = acceptance_met ] || { echo "[sift] $id not 'acceptance_met'" >&2; return 1; }
  log_append lane.transition acceptance_met reviewing "$id" >/dev/null
  mkdir -p "$SIFT_REVIEWS"
  local w2out; w2out="$(bash "$pd/acceptance/run.sh" "$pf" "$id" 2>/dev/null || true)"
  printf '%s' "$w2out" | _json_true passed \
    || { log_append lane.transition reviewing review_failed "$id" >/dev/null; echo "[sift] W2 reproduce failed: $(printf '%s' "$w2out" | _json_reason)" >&2; return 1; }
  w3mode="unknown"
  if [ -f "$pd/witness_w3.sh" ]; then
    w3out="$(bash "$pd/witness_w3.sh" "$pf" "$id" 2>/dev/null || true)"
    printf '%s' "$w3out" | _json_true ok \
      || { log_append lane.transition reviewing review_failed "$id" >/dev/null; echo "[sift] W3 rejected: $(printf '%s' "$w3out" | _json_reason)" >&2; return 1; }
    w3mode="$(printf '%s' "$w3out" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("w3_mode","unknown"))
except Exception: print("unknown")' 2>/dev/null || echo unknown)"
  else
    log_append lane.transition reviewing review_failed "$id" >/dev/null; echo "[sift] no keyless W3 (LLM W3 not wired in spine)" >&2; return 1
  fi
  local w4out; w4out="$(bash "$pd/witness_w4.sh" "$pf" "$id" 2>/dev/null || true)"
  printf '%s' "$w4out" | _json_true ok \
    || { log_append lane.transition reviewing review_failed "$id" >/dev/null; echo "[sift] W4 failed: $(printf '%s' "$w4out" | _json_reason)" >&2; return 1; }
  # Emit a CHAINED review.verdict event recording the real W3 verdict (=pass,
  # since we passed the fail-closed W3 gate above), then bind the terminal
  # confirmed event to that event by its event_hash. Authenticity now rides on
  # the tamper-evident chain, not a worker-writable side file (MP1-TRUST-CORE).
  w3h="$(_sift_sha < "$SIFT_REVIEWS/$id.w3.json")"
  fsha="$(git -C "$SIFT_REPO_ROOT" rev-parse HEAD 2>/dev/null || echo nogit)"
  esha="$(_sift_sha < "$pf")"
  vj="$(python3 -c 'import json,sys; print(json.dumps({"verdict":"pass","feature_sha":sys.argv[1],"w1_ok":True,"w2_ok":True,"w4_ok":True,"w3_hash":sys.argv[2],"w3_mode":sys.argv[3]}))' "$fsha" "$w3h" "${w3mode:-unknown}")"
  veh="$(log_append review.verdict reviewing reviewing "$id" "$vj")"
  we="$(python3 -c 'import json,sys; print(json.dumps({"verdict_event":sys.argv[1],"feature_sha":sys.argv[2],"extended_hash":sys.argv[3],"w1_ok":True,"w2_hash":"reproduced","w3_hash":sys.argv[4],"w4_hash":"w4-goal-addressed"}))' "$veh" "$fsha" "$esha" "$w3h")"
  log_append lane.transition reviewing confirmed "$id" "$we" >/dev/null
  rm -f "$SIFT_STATE/focus"   # work confirmed: release the scope-guard focus
  echo "[sift] confirmed $id (witness-bound to verdict event $veh)"
}
