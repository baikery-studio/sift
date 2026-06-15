#!/usr/bin/env bash
# kernel/setup.sh — bootstrap a working repo: create .harness state dirs + a
# default sift-harness.config.json. Idempotent (re-run is a no-op). The e2e
# entry point (criterion 4): sift setup -> author packet -> bin/sift -> confirmed.
_SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_SETUP_DIR/config.sh"

sift_setup() {
  root="${SIFT_REPO_ROOT:-$(pwd)}"
  mkdir -p "$root/.harness/reviews" "$root/.harness/runs" "$root/tasks/packets" "$root/evals/snapshots"
  # gitignore the append-only runtime state (.harness/ = hash-chained log + reviews + runs;
  # .canary/) so a user does not silently commit it. tasks/ and evals/ are NOT ignored —
  # packets and acceptance tests are the user's authored work, which they may commit.
  gi="$root/.gitignore"
  for _e in ".harness/" ".canary/"; do
    if [ ! -f "$gi" ] || ! grep -qxF "$_e" "$gi" 2>/dev/null; then printf '%s\n' "$_e" >> "$gi"; fi
  done
  cfg="$root/sift-harness.config.json"
  if [ ! -f "$cfg" ]; then
    python3 -c 'import json,sys
print(json.dumps({"paths":{"packets":"tasks/packets","snapshots":"evals/snapshots","state":".harness","reviews":".harness/reviews","canary":".canary"},"profile":"software"}, indent=2))' > "$cfg"
    echo "[sift] setup: wrote $cfg + .harness/"
  else
    echo "[sift] setup: already initialized (no-op)"
  fi
}
