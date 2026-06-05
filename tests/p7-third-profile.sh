#!/usr/bin/env bash
# selftest: the prose (third, non-code) profile exists and validates.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in profile.json acceptance/run.sh witness_w3.sh witness_w4.sh; do
  [ -f "$ROOT/profiles/prose/$f" ] || { echo "prose missing $f"; exit 1; }
done
python3 "$ROOT/kernel/_profile_validate.py" "$ROOT/profiles/prose/profile.json" >/dev/null 2>&1 || { echo "prose profile.json invalid"; exit 1; }
echo "PASS: prose profile present + validates"
