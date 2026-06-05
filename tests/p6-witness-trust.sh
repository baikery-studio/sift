#!/usr/bin/env bash
# selftest: string-literal mention doesn't pass W4; async def + string-only mention caught by W5.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; W4="$ROOT/profiles/software/witness_w4.sh"; DORMANT="$ROOT/kernel/_wave_dormant.py"
okf(){ python3 -c 'import json,sys
try: print("1" if json.load(sys.stdin).get("ok") else "0")
except Exception: print("err")'; }
t="$(mktemp -d)"; mkdir -p "$t/kernel"
printf 'ds() { :; }\nds\n' > "$t/kernel/a.sh"; printf 'X=["ds"]\n' > "$t/kernel/b.sh"
cat > "$t/p.md" <<'PK'
---
id: p
profile: software
goal: ds wiring
wiring_symbol: ds
wiring_min_hits: 2
---
PK
[ "$(SIFT_REPO_ROOT="$t" bash "$W4" "$t/p.md" p 2>/dev/null | okf)" = "0" ] || { echo "W4 passed a string-only 2nd-file mention"; exit 1; }
printf 'async def adef():\n    return 1\n' > "$t/kernel/c.py"
python3 "$DORMANT" "$t" kernel/c.py 2>/dev/null | grep -q adef || { echo "W5 missed async def"; exit 1; }
echo "PASS: W4/W5 ignore string-literal mentions; W5 detects async def"
