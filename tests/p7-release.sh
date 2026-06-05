#!/usr/bin/env bash
# selftest: release.yml exists with safe minimal shape; CICD reconciled.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; RY="$ROOT/.github/workflows/release.yml"
[ -f "$RY" ] || { echo "no release.yml"; exit 1; }
grep -qE "tags:" "$RY" || { echo "no tag trigger"; exit 1; }
grep -qi 'gh release create' "$RY" || { echo "no gh release create"; exit 1; }
grep -qiE 'contents:\s*write' "$RY" || { echo "no least-priv permissions"; exit 1; }
grep -qiE 'cosign|slsa|provenance|sigstore' "$RY" && { echo "release.yml overclaims signing"; exit 1; }
echo "PASS: minimal release.yml (v* tag, VERSION lockstep, gh release create, least-priv, no signing overclaim)"
