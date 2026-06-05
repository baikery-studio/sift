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
# Parse defensively. A garbled payload, or one whose tool_name/file_path contains
# a newline (a read-r split bypass), yields __PARSE_ERROR__ so the guard fails
# CLOSED while a focus is active — never silently allow on bad input.
read -r tool path <<EOF
$(printf '%s' "$payload" | python3 -c 'import json,sys
try:
    d=json.loads(sys.stdin.read())
    if not isinstance(d, dict): raise ValueError("payload is not a JSON object")
    tn=str(d.get("tool_name") or "_")
    ti=d.get("tool_input")
    if not isinstance(ti, dict): raise ValueError("tool_input is not an object")
    fp=str(ti.get("file_path") or ti.get("path") or "_")
    if any(c in tn+fp for c in "\n\r"): raise ValueError("newline in tool_name/file_path")
    print(tn, fp)
except Exception:
    print("__PARSE_ERROR__ _")')
EOF

decision="$(scope_guard_decision "$tool" "$path")" && exit 0
# non-zero from scope_guard_decision => DENY
echo "[sift scope-guard] $decision" >&2
exit 2
