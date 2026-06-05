#!/usr/bin/env bash
# Acceptance for ADO-4-FROMDIFF-CLEAN. RED before (harness noise leaks into scope), GREEN after.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }
# ADO-5: flags documented
for f in -- --paths --from-diff --profile; do grep -q -- "$f" "$ROOT/commands/sift-new.md" || fail "sift-new.md does not document $f"; done

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
export SIFT_REPO_ROOT="$w"; "$SIFT" setup >/dev/null 2>&1
( cd "$w" && git init -q && git config user.email t@t && git config user.name t \
   && mkdir -p src && echo a > src/real.ts && git add -A && git commit -qm init \
   && echo b >> src/real.ts )                                  # a real source change
# also dirty a harness-managed file + the config (the noise --from-diff must exclude)
echo noise >> "$w/sift-harness.config.json"
( cd "$w" && git add -A )
"$SIFT" packet new feat --profile toy --from-diff >/dev/null 2>&1 || fail "packet new --from-diff failed"
P="$w/tasks/packets/feat.md"
grep -q 'src/real.ts' "$P" || fail "real source change not seeded into scope"
grep -q 'sift-harness.config.json' "$P" && fail "config leaked into --from-diff scope (ADO-4 not applied)"
grep -qE '\.harness/' "$P" && fail ".harness/ leaked into --from-diff scope"
echo "PASS: --from-diff seeds real source only (harness noise excluded); flags documented"
