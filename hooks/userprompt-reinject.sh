#!/usr/bin/env bash
# hooks/userprompt-reinject.sh — Claude Code UserPromptSubmit adapter (HERD-2).
# Re-asserts the active-focus contract on each user prompt so a long turn does not drift
# off the loop. Emits additionalContext naming the active packet, the next verb, and the
# non-negotiable "confirmed before done" gate. Throttled on (packet,state) change so it
# informs rather than nags. Writes only its own throttle marker — never a lane.transition;
# the authoritative state stays the replayed log. ADVISORY (host-honored injection).
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-${SIFT_REPO_ROOT:-$(pwd)}}"
. "$HOOK_DIR/../kernel/state.sh"
SIFT_STATE="${SIFT_STATE:-$(config_path state)}"
focus="$SIFT_STATE/focus"

cat >/dev/null 2>&1 || true   # drain the prompt payload (unused)

# No active packet → no injection.
[ -f "$focus" ] || exit 0
id="$(head -n1 "$focus" 2>/dev/null | tr -d '[:space:]')"
[ -n "$id" ] || exit 0

st="$(project_state "$id" 2>/dev/null || echo unknown)"
case "$st" in
  packeted)        verb="sift execute $id" ;;
  acceptance_met)  verb="sift review $id" ;;
  reviewing)       verb="sift review $id" ;;
  confirmed)       exit 0 ;;   # nothing to herd toward
  *)               verb="sift state $id" ;;
esac

emit(){ python3 -c 'import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":sys.argv[1]}}))' "$1"; }

marker="$SIFT_STATE/reinject.last"
prev="$(cat "$marker" 2>/dev/null || true)"
now="$id:$st"

if [ "$prev" = "$now" ]; then
  # unchanged since last prompt → short reminder only (throttle)
  emit "sift: packet $id still in flight ($st). Reach confirmed before reporting done."
else
  mkdir -p "$SIFT_STATE" 2>/dev/null || true
  printf '%s' "$now" > "$marker" 2>/dev/null || true
  emit "ACTIVE SIFT PACKET: $id (state: $st). Next: run \`$verb\`. Edits are fenced to this packet's scope.paths by the scope guard. Do not report the task done until \`sift state $id\` is confirmed — completion is witness-bound, not asserted."
fi
exit 0
