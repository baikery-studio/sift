#!/usr/bin/env bash
# selftest: the PreToolUse scope guard blocks an out-of-scope edit and allows
# an in-scope one against the focus packet.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"; HOOK="$ROOT/hooks/pretooluse-scope.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
( cd "$work"; SIFT_REPO_ROOT="$work" "$SIFT" setup >/dev/null )
cat > "$work/tasks/packets/g.md" <<'EOF'
---
id: g
profile: software
goal: guard focus packet
scope:
  type: harness
  paths:
    - kernel/g.sh
wiring_exempt: true
---
EOF
decide() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2" \
  | SIFT_REPO_ROOT="$work" CLAUDE_PROJECT_DIR="$work" bash "$HOOK" >/dev/null 2>&1; }

SIFT_REPO_ROOT="$work" "$SIFT" focus g >/dev/null
decide Write kernel/g.sh   || { echo "in-scope edit wrongly denied"; exit 1; }
if decide Write kernel/x.sh; then echo "out-of-scope edit wrongly allowed"; exit 1; fi
decide Bash kernel/x.sh    || { echo "non-edit tool wrongly denied"; exit 1; }
SIFT_REPO_ROOT="$work" "$SIFT" focus --clear >/dev/null
decide Write kernel/x.sh   || { echo "after clear, edit wrongly denied"; exit 1; }
echo "PASS: PreToolUse scope guard fences edits to the focus packet's scope.paths"
