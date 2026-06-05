#!/usr/bin/env bash
# Acceptance for ADO-2-SCOPE-INFER. RED before (no --paths/--from-diff), GREEN after.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q -- '--from-diff' "$ROOT/kernel/scaffold.sh" || fail "scaffold has no --from-diff (RED)"

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
export SIFT_REPO_ROOT="$w"; "$SIFT" setup >/dev/null 2>&1

# 1. --paths seeds scope.paths with the given paths
"$SIFT" packet new p1 --profile toy --paths "src/a.ts,src/b.ts" >/dev/null 2>&1 || fail "packet new --paths failed"
grep -q 'src/a.ts' "$w/tasks/packets/p1.md" || fail "scope.paths missing src/a.ts"
grep -q 'src/b.ts' "$w/tasks/packets/p1.md" || fail "scope.paths missing src/b.ts"
grep -q 'tasks/packets/p1.md' "$w/tasks/packets/p1.md" || fail "packet path not auto-added"

# 2. --from-diff seeds from the working-tree diff
( cd "$w" && git init -q && git config user.email t@t && git config user.name t && \
  mkdir -p lib && echo x > lib/changed.ts && git add -A && git commit -qm init && echo y >> lib/changed.ts )
"$SIFT" packet new p2 --profile toy --from-diff >/dev/null 2>&1 || fail "packet new --from-diff failed"
grep -q 'lib/changed.ts' "$w/tasks/packets/p2.md" || fail "scope.paths not seeded from diff"

# 3. no flags → default placeholder scope
"$SIFT" packet new p3 --profile toy >/dev/null 2>&1 || fail "default packet new failed"
grep -q 'out/p3.txt' "$w/tasks/packets/p3.md" || fail "default scope placeholder missing"
echo "PASS: --paths and --from-diff seed scope.paths; default placeholder preserved"
