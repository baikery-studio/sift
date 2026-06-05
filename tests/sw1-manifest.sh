#!/usr/bin/env bash
# RED-first acceptance for SW-1-manifest: kernel/manifest.sh::manifest_write pins
# base_sha / feature_sha / extended_hash. RED on HEAD before manifest.sh exists.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ROOT/kernel/manifest.sh" ] || { echo "RED: kernel/manifest.sh absent"; exit 1; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT; cd "$work"
git init -q 2>/dev/null || true
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base 2>/dev/null || true
export SIFT_REPO_ROOT="$work" SIFT_STATE="$work/.harness"
. "$ROOT/kernel/manifest.sh"
mf="$(manifest_write demo abc123)"
[ -f "$mf" ] || { echo "manifest not written"; exit 1; }
python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
assert d["packet_id"]=="demo", d
assert d["extended_hash"]=="abc123", d
assert d.get("feature_sha") and d.get("base_sha"), d
assert d["schema"]=="manifest/v1", d' "$mf"
echo "PASS: manifest_write pins packet_id + base/feature_sha + extended_hash"
