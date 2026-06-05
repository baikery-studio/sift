#!/usr/bin/env bash
# selftest: `sift status` is read-only + present; PreCompact writes a breadcrumb.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
grep -q 'status)' "$SIFT" || { echo "no status verb"; exit 1; }
[ -f "$ROOT/kernel/status.sh" ] || { echo "no status.sh"; exit 1; }
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT; export SIFT_REPO_ROOT="$w"
"$SIFT" setup >/dev/null 2>&1
b="$(wc -c < "$w/.harness/log.jsonl" 2>/dev/null || echo 0)"
"$SIFT" status >/dev/null 2>&1 || { echo "status errored"; exit 1; }
a="$(wc -c < "$w/.harness/log.jsonl" 2>/dev/null || echo 0)"
[ "$b" = "$a" ] || { echo "status mutated the log"; exit 1; }
SIFT_REPO_ROOT="$w" bash "$ROOT/hooks/sessionstart.sh" --precompact phase1 >/dev/null 2>&1 || true
[ -f "$w/.harness/resume.breadcrumb" ] || { echo "no breadcrumb"; exit 1; }
echo "PASS: read-only sift status + PreCompact breadcrumb"
