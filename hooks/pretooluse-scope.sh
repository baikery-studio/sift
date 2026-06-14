#!/usr/bin/env bash
# hooks/pretooluse-scope.sh — PreToolUse host adapter (Phase-2 runtime scope guard).
# Reads the host's PreToolUse JSON on stdin ({tool_name, tool_input:{file_path}})
# and BLOCKS (exit 2 + stderr reason) an edit whose path is outside the active
# packet's scope.paths. Exits 0 (allow) otherwise.
#
# ADVISORY: this only protects when the host runs the hook. Wire it in Claude Code
# via .claude/settings.json PreToolUse; other CLIs via their pre-tool equivalent.
# It is not a kernel-level sandbox.
#
# Installed as a plugin, hooks/hooks.json wires this via ${CLAUDE_PLUGIN_ROOT}.
# Manual (non-plugin) wiring in .claude/settings.json, co-located in the repo:
#   {"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit|NotebookEdit",
#     "hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-scope.sh"}]}]}}
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-${SIFT_REPO_ROOT:-$(pwd)}}"
. "$HOOK_DIR/../kernel/scope_guard.sh"

payload="$(cat 2>/dev/null || true)"
# Parse defensively. For edit tools we check file_path; for Bash we extract the
# command's WRITE TARGET(S) — redirections (`>`, `>>`) and write-capable commands
# (tee/cp/mv/install/truncate/touch/rsync/dd, sed -i) — and check EACH against scope.
# fd-dups (2>&1) and /dev/null are not file writes. A garbled payload yields
# __PARSE_ERROR__ so the guard fails CLOSED while a focus is active.
# Bash write targets come from the SHARED module (hooks/_bash_write_targets.py), the single
# source of truth both this enforcing guard and the advisory posttool detector use — so the
# command set (incl. rm/mkdir/rmdir/chmod/chown/ln/tar/unzip + git checkout/restore/clean)
# can never drift between them. write_targets() returns the path operands, ["__OPAQUE_BASH__"]
# for a write whose targets can't be enumerated (guard fails CLOSED under focus), or [] for
# read-only. __PARSE_ERROR__ on a garbled payload (fails closed too).
parsed="$(printf '%s' "$payload" | HOOK_DIR="$HOOK_DIR" python3 -c 'import json,sys,os
sys.path.insert(0, os.environ.get("HOOK_DIR",""))
from _bash_write_targets import write_targets
try:
    d=json.loads(sys.stdin.read())
    if not isinstance(d,dict): raise ValueError
    tn=str(d.get("tool_name") or "_")
    ti=d.get("tool_input")
    if not isinstance(ti,dict): raise ValueError
    if any(c in tn for c in "\n\r"): raise ValueError
    paths=[]
    if tn=="Bash":
        paths=write_targets(str(ti.get("command") or ""))
    else:
        fp=str(ti.get("file_path") or ti.get("path") or "")
        if fp: paths=[fp]
    print(tn)
    for p in paths:
        if not any(c in p for c in "\n\r"): print(p)
except Exception:
    print("__PARSE_ERROR__")')"

tool="$(printf '%s\n' "$parsed" | sed -n '1p')"
paths="$(printf '%s\n' "$parsed" | sed -n '2,$p')"

if [ "$tool" = "__PARSE_ERROR__" ]; then
  decision="$(scope_guard_decision __PARSE_ERROR__ _)" && exit 0
  echo "[sift scope-guard] $decision" >&2; exit 2
fi

case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit|Bash) ;;
  *) exit 0 ;;                        # non-write tool → allow
esac
[ -n "$paths" ] || exit 0            # write tool but no file target (read-only Bash) → allow

while IFS= read -r p; do
  [ -n "$p" ] || continue
  decision="$(scope_guard_decision Write "$p")" || { echo "[sift scope-guard] $decision" >&2; exit 2; }
done <<EOF
$paths
EOF
exit 0
