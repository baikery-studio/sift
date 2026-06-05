#!/usr/bin/env bash
# selftest: edit-tool writes to .harness/ are DENIED by the scope guard; in-scope allowed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT; export SIFT_REPO_ROOT="$w"
cat > "$w/p.md" <<'PKT'
---
scope:
  type: harness
  paths:
    - kernel/foo.sh
---
PKT
python3 "$ROOT/kernel/_scope.py" "$w/p.md" ".harness/log.jsonl" 2>/dev/null && { echo "edit-tool write to .harness/ NOT denied"; exit 1; } || true
python3 "$ROOT/kernel/_scope.py" "$w/p.md" ".harness/reviews/x.w3.json" 2>/dev/null && { echo ".harness/reviews NOT denied"; exit 1; } || true
python3 "$ROOT/kernel/_scope.py" "$w/p.md" "kernel/foo.sh" 2>/dev/null || { echo "in-scope edit wrongly denied"; exit 1; }
echo "PASS: edit-tool writes to .harness/ denied; in-scope edits allowed"
