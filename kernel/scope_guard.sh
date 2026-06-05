#!/usr/bin/env bash
# kernel/scope_guard.sh — decide whether an edit is allowed under the active
# ("focus") packet's scope. The runtime half of the harness's scope discipline:
# the donor scope_check verifies the diff AFTER the fact; this fences the edit
# AT the moment of the write (via the PreToolUse host hook).
_GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_GUARD_DIR/config.sh"
SIFT_STATE="${SIFT_STATE:-$(config_path state)}"
SIFT_PACKETS="${SIFT_PACKETS:-$(config_path packets)}"

# scope_guard_decision TOOL PATH -> prints ALLOW|DENY <reason>; rc 0 allow, 2 deny.
scope_guard_decision() {
  local tool="${1:-}" path="${2:-}"
  local foc; foc="$(cat "$SIFT_STATE/focus" 2>/dev/null || true)"
  foc="$(printf '%s' "$foc" | tr -d '[:space:]')"   # whitespace-only focus == empty (caught below)
  case "$tool" in
    __PARSE_ERROR__)                           # unparseable/suspicious payload
      [ -n "$foc" ] && { echo "DENY (unparseable hook payload while focus=$foc — fail-closed)"; return 2; }
      echo "ALLOW (unparseable payload, no active focus)"; return 0 ;;
    Edit|Write|MultiEdit|NotebookEdit) ;;      # only fence edit tools
    *) echo "ALLOW (non-edit tool: $tool)"; return 0 ;;
  esac
  # tool is an edit tool here. Distinguish "no focus" (ALLOW) from "focus declared
  # but blank/missing-packet" (DENY) — a present-but-useless focus must not silently
  # disable the guard.
  if [ -z "$foc" ]; then
    [ -f "$SIFT_STATE/focus" ] && { echo "DENY (focus file present but empty — fail-closed)"; return 2; }
    echo "ALLOW (no focus packet set)"; return 0
  fi
  local pkt="$SIFT_PACKETS/$foc.md"
  [ -f "$pkt" ] || { echo "DENY (focus '$foc' packet file missing — fail-closed)"; return 2; }
  if python3 "$_GUARD_DIR/_scope.py" "$pkt" "$path" 2>/dev/null; then
    echo "ALLOW (in scope of $foc)"; return 0
  fi
  echo "DENY ($path is outside packet $foc scope.paths)"; return 2
}

# sift_focus [<id>|--clear] — show / set / clear the active packet.
sift_focus() {
  mkdir -p "$SIFT_STATE"
  if [ "$#" -eq 0 ]; then cat "$SIFT_STATE/focus" 2>/dev/null || echo "(no focus)"; return 0; fi
  if [ "$1" = "--clear" ]; then
    # also disarm the FORT-1 engage-gate marker — stop-block.sh names `sift focus --clear`
    # as the throwaway escape, so it must actually release the turn (code-review HIGH).
    rm -f "$SIFT_STATE/focus" "$SIFT_STATE/unpacketed-edit"; echo "[sift] focus cleared"; return 0; fi
  printf '%s\n' "$1" > "$SIFT_STATE/focus"; echo "[sift] focus: $1"
}
