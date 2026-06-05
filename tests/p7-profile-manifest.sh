#!/usr/bin/env bash
# selftest: profile.json validator accepts shipped profiles, rejects malformed, is wired.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; PV="$ROOT/kernel/_profile_validate.py"
for p in toy software; do
  python3 "$PV" "$ROOT/profiles/$p/profile.json" >/dev/null 2>&1 || { echo "shipped $p rejected"; exit 1; }
done
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
printf '{}\n' > "$t/e.json"; python3 "$PV" "$t/e.json" >/dev/null 2>&1 && { echo "accepted empty"; exit 1; }
grep -q '_profile_validate' "$ROOT/kernel/pipeline.sh" || { echo "validator not wired into plan"; exit 1; }
echo "PASS: shipped profiles validate; empty rejected; wired into sift_plan"
