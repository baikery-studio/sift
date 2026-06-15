#!/usr/bin/env bash
# hooks/posttool-reset.sh — Claude Code PostToolUse adapter (HERD-3).
# When a scoped file is edited AFTER the packet reached acceptance_met, the prior
# acceptance is stale. The replay trust-core already catches this at review time (a
# changed feature_sha breaks the witness binding); this surfaces it AT RUNTIME, the
# moment it happens, so the agent re-runs the loop instead of reviewing on stale work.
# Writes only a runtime hint marker ($SIFT_STATE/dirty.<id>) — never a lane.transition.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-${SIFT_REPO_ROOT:-$(pwd)}}"
. "$HOOK_DIR/../kernel/scope_guard.sh"   # scope_guard_decision + SIFT_STATE + config
. "$HOOK_DIR/../kernel/state.sh"         # project_state
SIFT_STATE="${SIFT_STATE:-$(config_path state)}"
focus="$SIFT_STATE/focus"

payload="$(cat 2>/dev/null || true)"
# Classify the tool into a write KIND the engage-gate cares about (FORT-5: Bash file writes
# count too, so a lazy agent can't escape the gate by writing via the shell — echo>, cat>,
# tee, cp/mv, sed -i, dd, a python open(...,'w'), etc. — not just the Edit/Write tools).
# Emits two tab-separated tokens: "<kind>\t<path>" where kind ∈ edit|bashwrite|other and
# path is the file_path for edit tools (or "_" for bash). Defensive parse → __PARSE_ERROR__.
read -r kind path <<EOF
$(printf '%s' "$payload" | HOOK_DIR="$HOOK_DIR" python3 -c 'import json,sys,os
sys.path.insert(0, os.environ.get("HOOK_DIR",""))
from _bash_write_targets import is_write as bash_writes   # SHARED with the enforcing guard
try:
    d=json.loads(sys.stdin.read())
    if not isinstance(d, dict): raise ValueError
    tn=str(d.get("tool_name") or "_")
    ti=d.get("tool_input")
    if not isinstance(ti, dict): raise ValueError
    if tn in ("Edit","Write","MultiEdit","NotebookEdit"):
        fp=str(ti.get("file_path") or ti.get("path") or "_")
        if any(c in fp for c in "\n\r\t"): raise ValueError
        print("edit\t"+fp)
    elif tn=="Bash":
        cmd=str(ti.get("command") or "")
        print(("bashwrite" if bash_writes(cmd) else "other")+"\t_")
    else:
        print("other\t_")
except Exception:
    print("__PARSE_ERROR__\t_")')
EOF

# UP-4 first-edit engage: a real edit/bashwrite in an UN-SET-UP repo (no .harness/, no
# config) means the harness is inert and the agent is un-herded — the most dangerous
# moment (a fresh repo, no loop) is exactly the one a setup-gated harness can't see.
# Emit an engage signal offering setup instead of silently passing.
if { [ "$kind" = "edit" ] || [ "$kind" = "bashwrite" ]; } \
   && [ ! -d "$SIFT_REPO_ROOT/.harness" ] && [ ! -f "$SIFT_REPO_ROOT/sift-harness.config.json" ]; then
  # ENGAGE-COLD-1: arm a DISTINCT cold-engage marker so the Stop hook can BLOCK on it (the
  # nudge alone let the turn end — the harness was advisory in exactly the moment it matters
  # most). The marker shares unpacketed-edit's lifecycle: reset per session by sessionstart.sh,
  # cleared by `sift focus --clear`, and treated as stale by stop-block once `sift setup` writes
  # config. Arming creates .harness/state/ as a side effect; stop-block keys the cold-engage
  # gate on config (the setup-completion marker), so that side effect does not satisfy "set up".
  mkdir -p "$SIFT_STATE" 2>/dev/null || true
  printf 'edited=%s\n' "${path:-via-bash}" > "$SIFT_STATE/cold-engage" 2>/dev/null || true
  # Also arm the FORT-1 marker: the edit is unpacketed regardless of setup state. Once the
  # agent runs `sift setup` (config appears), stop-block clears the now-stale cold-engage and
  # hands off to FORT-1 — so a cold edit cannot be laundered into a clean Stop by running setup
  # without ever driving the edit through a packet. cold-engage is checked first, so a STILL
  # cold repo offers `sift setup` (not `sift packet new`).
  printf 'edited=%s\n' "${path:-via-bash}" > "$SIFT_STATE/unpacketed-edit" 2>/dev/null || true
  python3 -c 'import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[1]}}))' \
    "[sift] no .harness/ in this repo — the harness is not set up and is inert (completion is NOT witness-checked). Run \`sift setup\` to engage it, then \`sift init-claudemd\` to make the loop a standing rule." 2>/dev/null \
  || echo "[sift] no .harness/ — not set up; run 'sift setup' to engage the harness (then 'sift init-claudemd' for the standing rule)" >&2
  exit 0
fi

# A Bash file-write with no active packet arms the engage-gate the same as an edit tool
# (FORT-5). It has no single scoped path, so it only arms the gate — the in-scope
# stale-acceptance check below applies to the edit tools.
if [ "$kind" = "bashwrite" ]; then
  if [ ! -f "$focus" ] && { [ -f "$SIFT_REPO_ROOT/sift-harness.config.json" ] || [ -d "$SIFT_REPO_ROOT/.harness" ]; }; then
    mkdir -p "$SIFT_STATE" 2>/dev/null || true
    printf 'edited=via-bash\n' > "$SIFT_STATE/unpacketed-edit" 2>/dev/null || true
  fi
  exit 0
fi

# Only edit tools past here.
[ "$kind" = "edit" ] || exit 0

# FORT-1 engage-gate: an edit with NO active packet, in a sift-set-up repo, is a freehand edit
# outside the loop. Arm the unpacketed-edit marker so the Stop hook refuses to end the turn
# until the agent drives the work through a packet (or clears focus). Reset per session by
# sessionstart.sh; cleared by `sift plan` once the agent engages.
if [ ! -f "$focus" ]; then
  if [ -f "$SIFT_REPO_ROOT/sift-harness.config.json" ] || [ -d "$SIFT_REPO_ROOT/.harness" ]; then
    mkdir -p "$SIFT_STATE" 2>/dev/null || true
    printf 'edited=%s\n' "$path" > "$SIFT_STATE/unpacketed-edit" 2>/dev/null || true
  fi
  exit 0
fi
id="$(head -n1 "$focus" 2>/dev/null | tr -d '[:space:]')"
[ -n "$id" ] || exit 0

# In scope of the focus packet? (rc 0 = in-scope; reuse the guard, don't reimplement.
# kind=edit means a real edit tool fired, so pass a representative edit-tool name.)
scope_guard_decision Edit "$path" >/dev/null 2>&1 || exit 0

# Only stale if the packet had already passed acceptance.
st="$(project_state "$id" 2>/dev/null || echo unknown)"
[ "$st" = "acceptance_met" ] || exit 0

mkdir -p "$SIFT_STATE" 2>/dev/null || true
printf 'edited=%s\n' "$path" > "$SIFT_STATE/dirty.$id" 2>/dev/null || true
python3 -c 'import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":sys.argv[1]}}))' \
  "scoped file $path changed after acceptance_met for $id; the prior acceptance is now stale. Re-run \`sift execute $id\` then \`sift review $id\` — do not review on stale work."
exit 0
