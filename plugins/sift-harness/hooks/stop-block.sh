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

# ENGAGE-COLD-1 cold-repo engage-gate: the agent edited code freehand in a repo with NO sift
# harness set up (cold-engage armed by posttool-reset.sh). Block offering `sift setup` — this
# is the one place herding was purely advisory (a fresh repo: no loop, no witness, no record),
# so close it fail-closed. Key "set up" on config (what `sift setup` writes), NOT on .harness/:
# arming the marker created .harness/state/, so a .harness check would wrongly read the cold
# repo as already engaged and wave the turn through. Once config exists the marker is stale —
# clear it and fall through to the normal warm gates below.
if [ ! -f "$focus" ] && [ -f "$SIFT_STATE/cold-engage" ]; then
  if [ ! -f "$SIFT_REPO_ROOT/sift-harness.config.json" ]; then
    emit_block "you edited code in a repo with no sift harness set up — completion here is NOT witness-checked. Run \`sift setup\` to engage the harness (then \`sift init-claudemd\` for the standing rule) and drive the work through a packet, or \`sift focus --clear\` if this was throwaway, before ending the turn."
    exit 0
  fi
  rm -f "$SIFT_STATE/cold-engage" 2>/dev/null || true   # config now exists → setup engaged, marker stale
fi

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
