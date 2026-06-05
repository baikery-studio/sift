#!/usr/bin/env bash
# kernel/next.sh — derive the wave's resume point from the LOG alone: the first
# member not yet `confirmed`. This is what makes the harness long-horizon — state
# lives in the replayable log, so a fresh process (post-compaction/restart)
# recomputes the correct next packet with zero in-memory carryover.
_NEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_NEXT_DIR/config.sh"; . "$_NEXT_DIR/state.sh"
SIFT_PACKETS="${SIFT_PACKETS:-$(config_path packets)}"

sift_next() {
  local wid="$1"
  local reporoot="${SIFT_REPO_ROOT:-$(pwd)}"
  # Resume reads ONLY the user repo's waves — never the plugin's own dev waves. (A
  # fallback to $SIFT_PLUGIN_ROOT/tasks/waves used to surface the harness's internal
  # wave, e.g. SW-1-manifest, in a fresh user install. A user with no wave gets a clean
  # "no wave manifest", not the harness's build backlog.)
  local man="$reporoot/tasks/waves/$wid.json"
  [ -f "$man" ] || { echo "[sift] no wave manifest: $wid" >&2; return 1; }
  # Parse members; FAIL HARD on a malformed manifest — never a false ALL-CONFIRMED.
  local members
  members="$(python3 -c 'import json,sys,re
try:
    m = json.load(open(sys.argv[1]))["members"]
    assert isinstance(m, list) and m, "members must be a non-empty list"
    assert all(isinstance(x, str) and re.match(r"^[A-Za-z0-9._-]+$", x) for x in m), \
        "each member id must be a slug [A-Za-z0-9._-] (no spaces/separators)"
except Exception as e:
    sys.stderr.write("malformed manifest: %s\n" % e); sys.exit(1)
print(" ".join(m))' "$man")" || { echo "[sift] malformed/empty wave manifest: $wid (refusing to resume)" >&2; return 2; }
  local m st
  for m in $members; do
    st="$(project_state "$m")"
    case "$st" in
      confirmed|superseded) continue ;;                      # done / retired — skip
      corrupt) echo "[sift] $m: log corrupt — refusing to emit a resume target (run: sift verify-log)" >&2; return 3 ;;
      *) printf '%s\n' "$m"; return 0 ;;
    esac
  done
  printf 'ALL-CONFIRMED\n'
}
