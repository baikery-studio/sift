#!/usr/bin/env bash
# Doc-vs-code regression gate (UP-5): every CI workflow named in an OPERATIONAL
# claim-doc must exist as a real .github/workflows/*.yml file. Audits the docs that
# tell a user what IS — README, CONTRIBUTING, INSTALL_VERIFICATION, HOSTS — not the
# design specs that describe a planned target pipeline (CICD.md etc.), nor the
# gitignored local review notes that never ship. A workflow named on a line marked
# Planned / NOT implemented is exempt (an honest roadmap mention is not a false claim).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLAIM_DOCS="README.md CONTRIBUTING.md docs/INSTALL_VERIFICATION.md docs/spec/HOSTS.md"
miss=0
for d in $CLAIM_DOCS; do
  [ -f "$ROOT/$d" ] || continue
  while IFS= read -r line; do
    case "$line" in *[Pp]lanned*|*"NOT implemented"*|*"not implemented"*) continue ;; esac
    for wf in $(printf '%s' "$line" | grep -oE '[a-z0-9._-]+\.yml' 2>/dev/null); do
      echo "$wf" | grep -qE 'review|ci|release|scorecard|codeql|smoke|bench' || continue
      if [ ! -f "$ROOT/.github/workflows/$wf" ]; then
        echo "FAIL: claim-doc $d names a workflow that does not exist: $wf" >&2; miss=1
      fi
    done
  done < "$ROOT/$d"
done
[ "$miss" = 0 ] || exit 1
echo "PASS: every workflow named in a claim-doc exists (doc-vs-code in sync)"
