#!/usr/bin/env bash
# selftest: install-attestation schema present + correct-code not mislabeled.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; IV="$ROOT/docs/INSTALL_VERIFICATION.md"
grep -iqE 'stale.*CLAUDE_PROJECT_DIR|CLAUDE_PROJECT_DIR.*stale' "$IV" && { echo "still mislabels correct code as stale"; exit 1; }
for f in date host steps result operator; do grep -iq "$f" "$IV" || { echo "attestation missing $f"; exit 1; }; done
grep -iqE 'not[_ ]observed|operator[- ]attested' "$IV" || { echo "live state not kept honest"; exit 1; }
echo "PASS: attestation schema present; live state honest; no stale-mislabel"
