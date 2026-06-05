#!/usr/bin/env bash
# hooks/stop-block.sh — Claude Code Stop hook adapter (HERD-1, live steering).
# Blocks ending the turn while a sift packet is planned-but-not-confirmed, so a weak
# agent cannot describe a plan and stop with the work unproven. Reads the SAME focus
# state the scope guard uses ($SIFT_STATE/focus, set by `sift plan`, cleared on
# confirmed) and the replay-derived packet state — no new state surface.
#
# Emits a Claude Code block decision on stdout: {"decision":"block","reason":...}.
# The JSON decision (not the exit code) is what blocks the Stop, mirroring
# claude-code-harness. ADVISORY: only protects under a host that honors Stop decisions
# (Claude Code does); the hash-chained trust-core is the hard backstop everywhere.
#
# Wiring (plugin): hooks/hooks.json registers this on Stop via ${CLAUDE_PLUGIN_ROOT}.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-${SIFT_REPO_ROOT:-$(pwd)}}"
. "$HOOK_DIR/../kernel/state.sh"
SIFT_STATE="${SIFT_STATE:-$(config_path state)}"
focus="$SIFT_STATE/focus"

cat >/dev/null 2>&1 || true   # drain the Stop payload (unused)

emit_block(){ python3 -c 'import json,sys;print(json.dumps({"decision":"block","reason":sys.argv[1]}))' "$1"; }

# FORT-1 engage-gate: no active packet, but the agent edited code freehand this session
# (marker armed by posttool-reset.sh, reset per session by sessionstart.sh) → block so the
# work gets driven through a packet instead of ending unproven.
if [ ! -f "$focus" ] && [ -f "$SIFT_STATE/unpacketed-edit" ]; then
  emit_block "you edited code this session without a sift packet. Run \`sift packet new <id>\` and drive it to a witness-bound confirmed, or \`sift focus --clear\` if this was throwaway, before ending the turn."
  exit 0
fi

# No active packet (and no freehand edit) → allow stop (emit nothing).
[ -f "$focus" ] || exit 0
id="$(head -n1 "$focus" 2>/dev/null | tr -d '[:space:]')"
[ -n "$id" ] || exit 0

# Compute state; FAIL CLOSED (block) if unreadable while a focus is active.
st="$(project_state "$id" 2>/dev/null || echo __ERR__)"
case "$st" in
  confirmed)
    exit 0 ;;                                  # work proven done → allow stop
  corrupt)
    emit_block "sift packet $id replays as CORRUPT — the completion chain is broken. Run \`sift verify-log\` / \`sift doctor\`; do not end the turn on a corrupt packet." ;;
  __ERR__|"")
    emit_block "sift packet $id: could not verify state — run \`sift doctor\` / \`sift verify-log\` before ending the turn." ;;
  *)
    emit_block "sift packet $id is '$st', not confirmed. Run \`sift execute $id\` then \`sift review $id\` to reach a witness-bound confirmed before ending the turn." ;;
esac
exit 0
