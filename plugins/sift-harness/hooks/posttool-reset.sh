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
$(printf '%s' "$payload" | python3 -c 'import json,sys,re
def bash_writes(c):
    # redirection to a real file (incl. >& file). Skip /dev/null|stderr|stdout and pure
    # fd-dups (>&1, 2>&1, >&2). A >& with a non-numeric target IS a file write.
    for m in re.finditer(r"(\d*)(>>?)(&?)\s*([^\s;|&<>]+)", c):
        fd, op, amp, tgt = m.groups()
        if tgt in ("/dev/null","/dev/stderr","/dev/stdout"): continue
        if amp and tgt.isdigit(): continue                 # >&1 / 2>&1 fd-dup, not a file
        if tgt.startswith("&"): continue
        return True
    # write-capable commands, anchored at a command position (start / after ; | & && ||)
    # so package managers (npm install / pip install) and names like dd-trace do NOT
    # false-positive (no apostrophes in this block: it is single-quoted python -c).
    if re.search(r"(?:^|[;|&]|&&|\|\|)\s*(tee|cp|mv|dd|install|truncate|patch|rsync|touch|"
                 r"rm|mkdir|rmdir|chmod|chown|ln|tar|unzip|gunzip|gzip)\b", c): return True
    if re.search(r"\b(curl|wget)\b[^|;]*\s-[oO]\b", c): return True          # download-to-file only
    if re.search(r"\bsed\b[^|;]*\s-i", c): return True                       # sed -i (in-place)
    if re.search(r"\b(perl|ruby)\b[^|;]*\s-[a-z]*i", c): return True         # perl/ruby -i
    if re.search(r"\b(python3?|node|ruby|perl)\b[^|;]*-e\b", c): return True # -e inline script (may write)
    if re.search(r"\bpython3?\b[^|;]*open\([^)]*,\s*[\"'"'"'][wax]", c): return True
    return False
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
