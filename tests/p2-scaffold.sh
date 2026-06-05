#!/usr/bin/env bash
# selftest: `sift packet new` scaffolds a sift-schema-valid packet + stub and refuses to clobber.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
(
  cd "$work"; export SIFT_REPO_ROOT="$work"; "$SIFT" setup >/dev/null
  "$SIFT" packet new s --profile toy >/dev/null || { echo "scaffold failed"; exit 1; }
  [ -f tasks/packets/s.md ] && [ -x evals/snapshots/s/test.sh ] || { echo "scaffold outputs missing"; exit 1; }
  "$SIFT" packet validate s >/dev/null 2>&1 || { echo "scaffolded packet failed sift validate"; exit 1; }
  if "$SIFT" packet new s --profile toy >/dev/null 2>&1; then echo "clobber not refused"; exit 1; fi
) || exit 1
echo "PASS: sift packet new scaffolds a valid packet + stub and refuses to clobber"
