#!/usr/bin/env bash
# selftest: the whole-file-SHA checkpoint was DROPPED (HD2-1). project_state always verifies
# the full chain, so a forged checkpoint.json cannot let a tampered log pass as clean.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/kernel/_checkpoint.py" ] && { echo "_checkpoint.py should be gone (dropped in HD2-1)"; exit 1; }
grep -q '_checkpoint' "$ROOT/kernel/_state.py" && { echo "_state.py still references the checkpoint"; exit 1; }
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
export SIFT_REPO_ROOT="$w" SIFT_LOG="$w/.harness/log.jsonl" SIFT_STATE="$w/.harness"
mkdir -p "$w/.harness/reviews"
. "$ROOT/kernel/log.sh"; . "$ROOT/kernel/state.sh"
log_append lane.transition submitted packeted cp >/dev/null
log_append lane.transition packeted executing cp >/dev/null
[ "$(project_state cp)" != corrupt ] || { echo "honest log reads corrupt"; exit 1; }
# tamper a line (stale event_hash) + write a matching forged checkpoint
python3 - "$SIFT_LOG" <<'PY'
import sys; L=open(sys.argv[1]).read().splitlines()
L[0]=L[0].replace('"to":"packeted"','"to":"executing"'); open(sys.argv[1],'w').write("\n".join(L)+"\n")
PY
python3 - "$SIFT_LOG" "$w/.harness/checkpoint.json" <<'PY'
import sys, hashlib, json
h=hashlib.sha256()
with open(sys.argv[1],'rb') as f:
    for c in iter(lambda: f.read(65536), b''): h.update(c)
json.dump({"file_sha":h.hexdigest(),"chain_ok":True}, open(sys.argv[2],'w'))
PY
[ "$(project_state cp)" = corrupt ] || { echo "forged checkpoint let a tampered log pass"; exit 1; }
echo "PASS: checkpoint dropped; forged checkpoint ignored; tamper caught by full verify"
