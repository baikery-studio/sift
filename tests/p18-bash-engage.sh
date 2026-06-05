#!/usr/bin/env bash
# Acceptance for FORT-5-BASH-ENGAGE. RED before (Bash not matched), GREEN after.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }
# matcher includes Bash
python3 -c 'import json,sys
h=json.load(open(sys.argv[1]))["hooks"]["PostToolUse"]
assert "Bash" in json.dumps(h), "PostToolUse matcher does not include Bash (RED)"' "$ROOT/hooks/hooks.json" || fail "Bash not in PostToolUse matcher"

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
export SIFT_REPO_ROOT="$w"; "$SIFT" setup >/dev/null 2>&1
post(){ printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$1" | SIFT_REPO_ROOT="$w" bash "$ROOT/hooks/posttool-reset.sh" >/dev/null 2>&1 || true; }
stop(){ printf '{}' | SIFT_REPO_ROOT="$w" bash "$ROOT/hooks/stop-block.sh" 2>/dev/null || true; }
armed(){ [ -f "$w/.harness/unpacketed-edit" ]; }
clear_marker(){ rm -f "$w/.harness/unpacketed-edit"; }

# WRITE commands arm the gate
clear_marker; post '"echo hi > out.txt"';        armed || fail "redirect write did not arm the gate"
clear_marker; post '"sed -i s/a/b/ src/f.ts"';   armed || fail "sed -i did not arm the gate"
clear_marker; post '"cat foo > bar.txt"';        armed || fail "cat redirect did not arm the gate"
clear_marker; post '"cp a.txt b.txt"';           armed || fail "cp did not arm the gate"
clear_marker; post '"touch newfile.py"';         armed || fail "touch did not arm the gate"
clear_marker; post '"perl -pi -e s/a/b/ f.pl"';  armed || fail "perl -pi did not arm the gate"
clear_marker; post '"curl -o out.bin https://x"'; armed || fail "curl -o did not arm the gate"
# and the Stop hook then blocks
clear_marker; post '"echo x >> log.txt"'; stop | grep -q '"block"' || fail "Stop did not block after a Bash write"

# READ-ONLY / non-write commands must NOT arm the gate (no false blocks on read sessions)
clear_marker; post '"ls -la"';                   ! armed || fail "ls armed the gate (false positive)"
clear_marker; post '"grep -r foo src"';          ! armed || fail "grep armed the gate (false positive)"
clear_marker; post '"cat file.txt"';             ! armed || fail "cat (read) armed the gate"
clear_marker; post '"some_cmd 2>/dev/null"';     ! armed || fail "stderr redirect armed the gate"
clear_marker; post '"echo hi > /dev/null"';      ! armed || fail "write to /dev/null armed the gate"
clear_marker; post '"npm install lodash"';       ! armed || fail "npm install armed the gate (anchor false positive)"
clear_marker; post '"curl https://example.com"'; ! armed || fail "curl without -o armed the gate"
clear_marker; post '"build 2>&1"';               ! armed || fail "fd-dup 2>&1 armed the gate"

echo "PASS: Bash file-writes arm the engage-gate (Stop blocks); read-only Bash does not"
