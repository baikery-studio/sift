#!/usr/bin/env bash
# RED-first for SW-3: `sift setup` bootstraps a fresh repo (idempotent), enabling
# the e2e path setup -> author packet -> confirmed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/kernel/setup.sh" ] || { echo "RED: kernel/setup.sh absent"; exit 1; }
. "$ROOT/kernel/setup.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
export SIFT_REPO_ROOT="$work"
sift_setup >/dev/null
[ -d "$work/.harness/reviews" ] || { echo "setup did not create .harness/reviews"; exit 1; }
[ -d "$work/tasks/packets" ] || { echo "setup did not create tasks/packets"; exit 1; }
[ -f "$work/sift-harness.config.json" ] || { echo "setup did not write config"; exit 1; }
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));assert d["paths"]["packets"]=="tasks/packets";assert d["profile"]=="software"' "$work/sift-harness.config.json"
# idempotent: second run is a no-op (does not error)
out2="$(sift_setup)"; printf '%s' "$out2" | grep -q "no-op" || { echo "second setup should be a no-op"; exit 1; }
echo "PASS: sift setup bootstraps .harness + config; idempotent on re-run"
