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

# TAMPER-REVIEW-1: re-run the anti-tamper signature scan at REVIEW time over the packet's whole
# committed CHANGED-FILE SET, not just the two files the execute-time gate sees. A weakened
# sibling test, a commented-out assert, a continue-on-error, an early-return that dead-codes a
# test — introduced into ANY changed file after execute — would otherwise ride to a clean
# `confirmed` (sift_review never re-scanned). Review fails closed on a dirty tree, so the
# meaningful set is the committed diff: prefer the pinned manifest's base_sha..HEAD, then
# HEAD~1..HEAD, then the working diff. No git -> nothing committed to scan (return clean).
# Reuses the EXISTING _signatures.py scanner and blocking semantics; trust core untouched.
_signatures_gate_review() {
  local id="$1" root="$SIFT_REPO_ROOT" base="" man range="" tmpd rc=0
  git -C "$root" rev-parse HEAD >/dev/null 2>&1 || return 0
  man="$(ls -1t "$SIFT_STATE/runs/$id/"*.json 2>/dev/null | head -1)"
  if [ -n "$man" ]; then
    base="$(python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("base_sha","") or "")
except Exception: print("")' "$man" 2>/dev/null || true)"
  fi
  # Resolve the commit RANGE base..HEAD: the pinned manifest base (when it is a real ancestor
  # distinct from HEAD), else HEAD~1..HEAD. Empty range => a single-commit repo (no parent).
  if [ -n "$base" ] && [ "$base" != nogit ] && git -C "$root" rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 \
     && [ "$(git -C "$root" rev-parse "$base" 2>/dev/null)" != "$(git -C "$root" rev-parse HEAD 2>/dev/null)" ]; then
    range="$base..HEAD"
  elif git -C "$root" rev-parse --verify --quiet HEAD~1 >/dev/null 2>&1; then
    range="HEAD~1..HEAD"
  fi
  tmpd="$(mktemp -d)"
  local -a _rv_files=()
  if [ -n "$range" ]; then
    # Scan the content of every file touched in EVERY commit in the range, AT THAT COMMIT — not
    # just the net base..HEAD diff. A file added in one commit and deleted in a later one (to
    # hide a tamper from the net diff) is still scanned at the commit that introduced it. The
    # path is reconstructed under a tmp dir so _signatures.py's path-based test-file detection
    # (e.g. tests/foo_test.py) still matches.
    while IFS= read -r sha; do
      [ -n "$sha" ] || continue
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        git -C "$root" cat-file -e "$sha:$f" 2>/dev/null || continue   # deleted at this commit
        # Namespace the snapshot by commit SHA: the same path touched in multiple commits must
        # NOT overwrite (git log is newest-first, so a clean->tamper->clean sandwich on one file
        # would otherwise leave only the final clean version on disk, hiding the tampered middle
        # commit). The path suffix is preserved so _signatures.py still detects tests/foo_test.py.
        mkdir -p "$tmpd/$sha/$(dirname "$f")" 2>/dev/null || continue
        git -C "$root" show "$sha:$f" > "$tmpd/$sha/$f" 2>/dev/null || continue
        _rv_files+=("$tmpd/$sha/$f")
      done < <(git -C "$root" diff-tree --no-commit-id -r --name-only "$sha" 2>/dev/null)
    done < <(git -C "$root" log --format=%H "$range" 2>/dev/null)
  else
    # Single-commit repo (no parent to diff against): scan the whole tracked HEAD tree, which IS
    # the shipped set — so a tamper committed in the initial commit cannot pass unscanned.
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ -f "$root/$f" ] && _rv_files+=("$root/$f")
    done < <(git -C "$root" ls-files 2>/dev/null)
  fi
  if [ "${#_rv_files[@]}" -gt 0 ]; then
    python3 "$SIFT_PLUGIN_ROOT/kernel/_signatures.py" "${_rv_files[@]}"; rc=$?
  fi
  rm -rf "$tmpd" 2>/dev/null || true
  return $rc
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
    *) local _hint
       case "$cur" in
         submitted)               _hint="run \`sift plan $id\` first" ;;
         acceptance_met)          _hint="already executed — run \`sift review $id\`" ;;
         reviewing)               _hint="stuck in review — \`sift abort $id\` then re-execute" ;;
         confirmed|partially_confirmed) _hint="already done (\`sift state $id\`)" ;;
         unknown)                 _hint="no such packet — \`sift packet new $id\` or check the id" ;;
         corrupt)                 _hint="log reads corrupt — \`sift verify-log\`" ;;
         *)                       _hint="check \`sift state $id\`" ;;
       esac
       echo "[sift] $id not executable from '$cur' -> next: $_hint" >&2; return 1 ;;
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
  local _rs; _rs="$(project_state "$id")"
  if [ "$_rs" != acceptance_met ]; then
    local _h
    case "$_rs" in
      submitted)                      _h="run \`sift plan $id\` then \`sift execute $id\`" ;;
      packeted|failed|review_failed)  _h="run \`sift execute $id\` first" ;;
      confirmed|partially_confirmed)  _h="already confirmed (\`sift state $id\`)" ;;
      unknown)                        _h="no such packet — check the id" ;;
      *)                              _h="check \`sift state $id\`" ;;
    esac
    echo "[sift] $id not 'acceptance_met' (is '$_rs') -> next: $_h" >&2; return 1
  fi
  log_append lane.transition acceptance_met reviewing "$id" >/dev/null
  mkdir -p "$SIFT_REVIEWS"
  # W2 reproduce: independent, from clean (committed) state, writing a REAL artifact.
  # A clean tree means the reproduce reflects feature_sha, not uncommitted work; a dirty
  # tree fails closed with an actionable message.
  local w2art="$SIFT_REVIEWS/$id.w2.json" w2mode="fresh_clone_unavailable" w2root="$SIFT_REPO_ROOT" _w2wt=""
  if git -C "$SIFT_REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    if [ -n "$(git -C "$SIFT_REPO_ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      log_append lane.transition reviewing review_failed "$id" >/dev/null
      echo "[sift] W2 reproduce: uncommitted changes — commit before review" >&2; return 1
    fi
  fi
  # TAMPER-REVIEW-1: re-scan the committed changed set for anti-tamper signatures BEFORE minting
  # the terminal. The execute-time gate only saw two files; a weakened sibling test introduced
  # after execute is caught here. Same fail-closed semantics as the execute gate.
  if ! _signatures_gate_review "$id" 2>>"$SIFT_STATE/signatures.log"; then
    log_append lane.transition reviewing review_failed "$id" >/dev/null
    echo "[sift] review: anti-tamper signature hit in the changed set (see $SIFT_STATE/signatures.log) — fix the flagged file and re-execute" >&2; return 1
  fi
  # CONTAINMENT (W2-WORKTREE security review): the packet's `test:` becomes `cd <root> && bash
  # <test>` and is copied into the worktree, so a path that escapes the repo root (absolute, or
  # any `..` component) would read/execute/write OUTSIDE the clean checkout, defeating the
  # isolation. Reject such a packet fail-closed BEFORE any worktree/copy/run touches it.
  local _tc; _tc="$(packet_field "$id" test 2>/dev/null || true)"
  case "$_tc" in
    /*|../*|*/../*|*/..)
      log_append lane.transition reviewing review_failed "$id" >/dev/null
      echo "[sift] W2: packet test path '$_tc' is not repo-contained (no absolute or .. paths) — review_failed" >&2; return 1 ;;
  esac
  # W2-WORKTREE: a TRUE clean-checkout reproduce — run the acceptance from a detached git
  # worktree of feature_sha in a temp dir, NOT in-place on the working tree, so untracked /
  # gitignored / uncommitted state cannot leak into "reproduces". The acceptance TEST is the
  # verification oracle, not feature state: if the test path is gitignored (e.g. the snapshot
  # test) it is absent from the worktree, so copy it in — the committed FEATURE is still what
  # runs, so an untracked FEATURE dependency is correctly absent and fails the reproduce. Fall
  # back to an in-place run recorded as the fresh_clone_unavailable soft floor only when git /
  # the worktree is genuinely unavailable.
  local _fsha
  if git -C "$SIFT_REPO_ROOT" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    _fsha="$(git -C "$SIFT_REPO_ROOT" rev-parse HEAD 2>/dev/null)"
    _w2wt="$(mktemp -d)"
    if git -C "$SIFT_REPO_ROOT" worktree add --detach "$_w2wt" "$_fsha" >/dev/null 2>&1; then
      w2root="$_w2wt"; w2mode="clean_checkout"
      if [ -n "$_tc" ] && [ -f "$SIFT_REPO_ROOT/$_tc" ] && [ ! -f "$_w2wt/$_tc" ]; then
        mkdir -p "$_w2wt/$(dirname "$_tc")" 2>/dev/null || true
        cp "$SIFT_REPO_ROOT/$_tc" "$_w2wt/$_tc" 2>/dev/null || true
      fi
    else
      rm -rf "$_w2wt" 2>/dev/null || true; _w2wt=""    # worktree unavailable -> in-place floor
    fi
  fi
  local w2out; w2out="$(SIFT_REPO_ROOT="$w2root" bash "$pd/acceptance/run.sh" "$pf" "$id" 2>/dev/null || true)"
  if [ -n "$_w2wt" ]; then
    git -C "$SIFT_REPO_ROOT" worktree remove --force "$_w2wt" >/dev/null 2>&1 || rm -rf "$_w2wt" 2>/dev/null || true
  fi
  printf '%s' "$w2out" | _json_true passed \
    || { log_append lane.transition reviewing review_failed "$id" >/dev/null; echo "[sift] W2 reproduce failed ($w2mode): $(printf '%s' "$w2out" | _json_reason)" >&2; return 1; }
  python3 -c 'import json,sys
try: acc=json.loads(sys.argv[2])
except Exception: acc={}
print(json.dumps({"w2":"reproduced","mode":sys.argv[1],"acceptance":acc}))' "$w2mode" "$w2out" > "$w2art"
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
  local w4art="$SIFT_REVIEWS/$id.w4.json"
  local w4out; w4out="$(bash "$pd/witness_w4.sh" "$pf" "$id" 2>/dev/null || true)"
  printf '%s' "$w4out" | _json_true ok \
    || { log_append lane.transition reviewing review_failed "$id" >/dev/null; echo "[sift] W4 failed: $(printf '%s' "$w4out" | _json_reason)" >&2; return 1; }
  printf '%s\n' "$w4out" > "$w4art"
  # WITNESS-PLATFORM: run any ADDITIONAL review witnesses the profile declares beyond the kernel
  # defaults (w2 reproduce, w3 review, w4 wiring), so a profile adds a coverage/security/perf/
  # dependency witness WITHOUT kernel surgery. Each declared {impl, artifact}: invoke the impl,
  # fail closed on a non-ok verdict, then hash the declared artifact and bind it as <id>_hash.
  # The default software profile declares only w3/w4, so this loop is EMPTY and the default path
  # is byte-identical (w2/w3/w4 above are untouched). _state.py binds whatever w*_hash keys are
  # present, so an extra witness here cannot be left unbound.
  local _extra_we="{}" _wid _wimpl _wsuf
  while IFS="	" read -r _wid _wimpl _wsuf; do
    [ -n "$_wid" ] || continue
    # The witness id becomes the binding key <id>_hash that _state.py verifies via ^w\w+_hash$.
    # Reject any id the replay would NOT bind (a `.`/`/`/space in the id), so the producer and
    # the validator agree: a witness this runs is a witness replay verifies (no fail-open gap).
    printf '%s' "$_wid" | grep -qE '^w[A-Za-z0-9_]+$' \
      || { log_append lane.transition reviewing review_failed "$id" >/dev/null; echo "[sift] invalid declared witness id '$_wid' (must match w[A-Za-z0-9_]+) — review_failed" >&2; return 1; }
    if [ -z "$_wimpl" ] || [ ! -f "$pd/$_wimpl" ]; then
      log_append lane.transition reviewing review_failed "$id" >/dev/null
      echo "[sift] declared witness '$_wid' has no impl ($_wimpl) — review_failed" >&2; return 1
    fi
    local _wout; _wout="$(bash "$pd/$_wimpl" "$pf" "$id" 2>/dev/null || true)"
    printf '%s' "$_wout" | _json_true ok \
      || { log_append lane.transition reviewing review_failed "$id" >/dev/null; echo "[sift] declared witness '$_wid' failed: $(printf '%s' "$_wout" | _json_reason)" >&2; return 1; }
    local _wsfx="${_wsuf:-.$_wid.json}" _wart _whash
    _wart="$SIFT_REVIEWS/$id$_wsfx"
    [ -f "$_wart" ] \
      || { log_append lane.transition reviewing review_failed "$id" >/dev/null; echo "[sift] declared witness '$_wid' wrote no artifact ($_wsfx) — review_failed" >&2; return 1; }
    _whash="$(_sift_sha < "$_wart")"
    _extra_we="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d[sys.argv[2]+"_hash"]=sys.argv[3]; print(json.dumps(d))' "$_extra_we" "$_wid" "$_whash")"
  done <<EOF
$(python3 -c 'import json,sys
try: w=json.load(open(sys.argv[1])).get("witnesses",{})
except Exception: w={}
for wid in sorted(w):
    if wid in ("w2","w3","w4"): continue
    e=w[wid] if isinstance(w[wid],dict) else {}
    print("%s\t%s\t%s" % (wid, e.get("impl",""), e.get("artifact","")))' "$pd/profile.json" 2>/dev/null || true)
EOF
  # Emit a CHAINED review.verdict event recording the real W3 verdict (=pass,
  # since we passed the fail-closed W3 gate above), then bind the terminal
  # confirmed event to that event by its event_hash. Authenticity now rides on
  # the tamper-evident chain, not a worker-writable side file (MP1-TRUST-CORE).
  w2h="$(_sift_sha < "$w2art")"
  w3h="$(_sift_sha < "$SIFT_REVIEWS/$id.w3.json")"
  w4h="$(_sift_sha < "$w4art")"
  fsha="$(git -C "$SIFT_REPO_ROOT" rev-parse HEAD 2>/dev/null || echo nogit)"
  # PIN the packet bytes into the reviews dir so extended_hash binds to a stable artifact
  # that travels with .harness/reviews (the mutable tasks/packets file is gitignored and
  # archived after confirm). _state.py re-derives extended_hash from this snapshot.
  local pktart="$SIFT_REVIEWS/$id.packet"
  cp "$pf" "$pktart"
  esha="$(_sift_sha < "$pktart")"
  # the verdict event records ALL THREE real witness-artifact hashes; the terminal
  # confirmed event binds to them (and to the re-derivable extended_hash). _state.py
  # rejects any of these that does not match its on-disk artifact at replay.
  # vj/we carry the default w2/w3/w4 hashes PLUS any extra declared-witness hashes (_extra_we).
  # When _extra_we is "{}" (default profile) the result is byte-identical to the w2/w3/w4-only
  # form; the event_hash is canon(sorted-keys) so field order never matters.
  vj="$(python3 -c 'import json,sys; d=json.loads(sys.argv[6]); d.update({"verdict":"pass","feature_sha":sys.argv[1],"w1_ok":True,"w2_hash":sys.argv[2],"w3_hash":sys.argv[3],"w4_hash":sys.argv[4],"w3_mode":sys.argv[5]}); print(json.dumps(d))' "$fsha" "$w2h" "$w3h" "$w4h" "${w3mode:-unknown}" "$_extra_we")"
  veh="$(log_append review.verdict reviewing reviewing "$id" "$vj")"
  # w3_mode is ADDITIVE / OPTIONAL evidence (W3-SEM-1): it lets a second party prove which
  # review regime ran (host R1-R13 vs keyless structural floor). It is NOT in _state.py
  # REQUIRED_WE — every pre-existing confirmed lacks it and must still replay clean, so its
  # absence can never corrupt a confirmed. _state.py does not compare it, so adding it here is
  # safe; _audit.py surfaces it.
  we="$(python3 -c 'import json,sys; d=json.loads(sys.argv[8]); d.update({"verdict_event":sys.argv[1],"feature_sha":sys.argv[2],"extended_hash":sys.argv[3],"w1_ok":True,"w2_hash":sys.argv[4],"w3_hash":sys.argv[5],"w4_hash":sys.argv[6],"w3_mode":sys.argv[7]}); print(json.dumps(d))' "$veh" "$fsha" "$esha" "$w2h" "$w3h" "$w4h" "${w3mode:-unknown}" "$_extra_we")"
  # Soft-floor cap (operator-acknowledged): if the packet declares an accepted soft_floor,
  # validate it against the profile's soft_floors[].category allowlist. A KNOWN category
  # caps the terminal to partially_confirmed (still witness-bound). An UNKNOWN category
  # fails closed (review_failed). No declaration -> full confirmed.
  local terminal=confirmed sfloor
  sfloor="$(packet_field "$id" soft_floor 2>/dev/null || true)"
  if [ -n "$sfloor" ]; then
    if python3 -c 'import json,sys
try: cats=[f.get("category") for f in json.load(open(sys.argv[1])).get("soft_floors",[])]
except Exception: cats=[]
sys.exit(0 if sys.argv[2] in cats else 1)' "$pd/profile.json" "$sfloor"; then
      terminal=partially_confirmed
    else
      log_append lane.transition reviewing review_failed "$id" >/dev/null
      echo "[sift] unknown soft_floor '$sfloor' (not in profile soft_floors) — review_failed" >&2; return 1
    fi
  fi
  log_append lane.transition reviewing "$terminal" "$id" "$we" >/dev/null
  rm -f "$SIFT_STATE/focus"   # work resolved: release the scope-guard focus
  if [ "$terminal" = partially_confirmed ]; then
    echo "[sift] partially_confirmed $id (soft_floor: $sfloor; witness-bound to verdict event $veh)"
  else
    echo "[sift] confirmed $id (witness-bound to verdict event $veh)"
  fi
}
