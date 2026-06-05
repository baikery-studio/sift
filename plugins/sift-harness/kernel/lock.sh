#!/usr/bin/env bash
# kernel/lock.sh — single-dispatch lock (WIP=1) with PID-liveness stale reclaim.
_LOCKSH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_LOCKSH_DIR/config.sh"
SIFT_STATE="${SIFT_STATE:-$(config_path state)}"

sift_lock_acquire() { # PACKET_ID
  mkdir -p "$SIFT_STATE"
  if mkdir "$SIFT_STATE/dispatch.lock.d" 2>/dev/null; then
    printf '%s\n' "$$" > "$SIFT_STATE/dispatch.lock.d/pid"
    printf '%s\n' "$1" > "$SIFT_STATE/active"
    return 0
  fi
  pid=$(cat "$SIFT_STATE/dispatch.lock.d/pid" 2>/dev/null || echo "")
  # Reclaim if the claim has NO live owner: an empty/missing PID (a half-written
  # claim) OR a PID no longer running. An empty PID must not wedge WIP=1 forever.
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    # ATOMIC steal (HD2-2): rename the stale lock dir to a per-process tombstone. `mv` of a
    # directory is atomic, so if two reclaimers race only ONE rename of the same source
    # succeeds; the loser's mv fails (source already gone) → it returns 1 and retries. This
    # removes the rm-then-mkdir window where a reclaimer could delete another's fresh lock.
    tomb="$SIFT_STATE/dispatch.lock.reclaim.$$"
    rm -rf "$tomb" 2>/dev/null || true
    if mv "$SIFT_STATE/dispatch.lock.d" "$tomb" 2>/dev/null; then
      rm -rf "$tomb"
      if mkdir "$SIFT_STATE/dispatch.lock.d" 2>/dev/null; then
        printf '%s\n' "$$" > "$SIFT_STATE/dispatch.lock.d/pid"
        printf '%s\n' "$1" > "$SIFT_STATE/active"
        return 0
      fi
    fi
  fi
  return 1
}

sift_lock_release() {
  rm -rf "$SIFT_STATE/dispatch.lock.d" "$SIFT_STATE/active" 2>/dev/null || true
}
