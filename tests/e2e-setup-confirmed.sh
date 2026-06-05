#!/usr/bin/env bash
# E2E (criterion 4): a fresh repo, sift setup -> author a packet -> bin/sift
# plan/execute/review -> confirmed. Keyless (toy profile), so it runs in CI/W5.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT; cd "$work"
export SIFT_REPO_ROOT="$work"
"$SIFT" setup >/dev/null
mkdir -p out
cat > tasks/packets/e2e-toy.md <<'EOF'
---
id: e2e-toy
profile: toy
goal: produce an e2e greeting artifact carrying the marker
artifact:
  path: out/e.txt
  marker: E2E-OK
---
EOF
printf 'an e2e greeting produced end to end\nE2E-OK\n' > out/e.txt
"$SIFT" plan e2e-toy >/dev/null
"$SIFT" execute e2e-toy >/dev/null
"$SIFT" review e2e-toy >/dev/null
[ "$("$SIFT" state e2e-toy)" = confirmed ] || { echo "e2e packet not confirmed"; exit 1; }
echo "PASS: e2e  setup -> author -> plan/execute/review -> confirmed"
