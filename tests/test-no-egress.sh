#!/usr/bin/env bash
# selftest: sift has NO network egress. The W3 review is keyless-only — no redaction
# module, no consent flag, no network backends, no egress log. Guards the removal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
[ -e "$ROOT/kernel/_redact.py" ] && fail "kernel/_redact.py is back (egress should be gone)"
[ -d "$ROOT/profiles/software/w3-backends" ] && fail "w3-backends/ is back (network backends should be gone)"
git -C "$ROOT" ls-files profiles kernel | xargs grep -lE 'SIFT_W3_EGRESS|egress.log|_redact' 2>/dev/null | grep -q . \
  && fail "an egress reference (SIFT_W3_EGRESS / egress.log / _redact) survives in kernel/profiles"
# software W3 is keyless mode
python3 -c 'import json,sys
w3=json.load(open(sys.argv[1]))["witnesses"]["w3"]
assert w3.get("mode")=="keyless" and "backend" not in w3, "software W3 must be keyless-only"' \
  "$ROOT/profiles/software/profile.json" || fail "software profile W3 is not keyless-only"
# the witness contains the keyless check and no network dispatch
grep -q 'keyless' "$ROOT/profiles/software/witness_w3.sh" || fail "witness_w3 lost the keyless path"
grep -qE '_egress_consented|_w3_resolve_backend|bash .*adapter' "$ROOT/profiles/software/witness_w3.sh" && fail "witness_w3 still has backend/egress dispatch"
# SECURITY discloses no network egress
grep -qiE 'no network|makes no network|no.*egress' "$ROOT/SECURITY.md" || fail "SECURITY.md does not state no-network-egress"
echo "PASS: no egress — keyless-only W3, no redaction/consent/network-backend/egress-log, SECURITY says nothing leaves"
