#!/usr/bin/env bash
# selftest: scope guard fails CLOSED on non-object JSON + missing packet; glob
# does not cross '/'.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
HOOK="$ROOT/hooks/pretooluse-scope.sh"; SCOPE="$ROOT/kernel/_scope.py"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
( cd "$work"; SIFT_REPO_ROOT="$work" "$SIFT" setup >/dev/null )
cat > "$work/tasks/packets/g.md" <<'EOF'
---
id: g
profile: software
goal: guard focus
scope:
  type: harness
  paths: [kernel/seg/*.sh]
wiring_exempt: true
---
EOF
SIFT_REPO_ROOT="$work" "$SIFT" focus g >/dev/null
hp(){ printf '%s' "$1" | SIFT_REPO_ROOT="$work" CLAUDE_PROJECT_DIR="$work" bash "$HOOK" >/dev/null 2>&1; }
if hp 'null'; then echo "fail-open on null JSON"; exit 1; fi
if hp '[]'; then echo "fail-open on array JSON"; exit 1; fi
rm -f "$work/tasks/packets/g.md"
if hp '{"tool_name":"Write","tool_input":{"file_path":"kernel/x.sh"}}'; then echo "fail-open on missing packet"; exit 1; fi
if SIFT_REPO_ROOT="$work" python3 "$SCOPE" <(printf -- '---\nscope:\n  type: h\n  paths: [kernel/seg/*.sh]\n---\n') "kernel/seg/deep/x.sh" 2>/dev/null; then echo "glob crossed /"; exit 1; fi
echo "PASS: scope guard fail-closed (non-object JSON, missing packet); glob no-cross-slash"
