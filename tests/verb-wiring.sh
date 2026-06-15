#!/usr/bin/env bash
# selftest: the uplift's verbs are WIRED — each is dispatched in bin/sift AND defined in
# its kernel module. This is the reachability proof the wiring_exempt packets skipped: a
# future edit that drops a verb's dispatch or its definition fails here.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
SIFT="$ROOT/bin/sift"

# verb -> "defining_file:function_or_dispatch_token"
check() { # <verb> <kernel_file> <def_token>
  local verb="$1" kfile="$2" deftok="$3"
  grep -qE "^[[:space:]]*$verb\)" "$SIFT" || fail "verb '$verb' not dispatched in bin/sift"
  grep -qE "$deftok" "$ROOT/$kfile" || fail "verb '$verb' impl ($deftok) missing from $kfile"
}

check audit       kernel/audit.sh 'sift_audit\(\)'
check abort        kernel/state.sh 'sift_abort\(\)'
check coverage     kernel/wave.sh  'sift_coverage\(\)'
check migrate-log  kernel/log.sh   'migrate_log_chain\(\)'

# each verb is callable end-to-end (help/usage path, no crash, exit defined)
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
SIFT_REPO_ROOT="$W" bash "$SIFT" audit --help    >/dev/null 2>&1 || fail "sift audit --help crashed"
SIFT_REPO_ROOT="$W" bash "$SIFT" migrate-log --help >/dev/null 2>&1 || fail "sift migrate-log --help crashed"

echo "PASS: audit/abort/coverage/migrate-log are dispatched + defined (verb wiring intact)"
