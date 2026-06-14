#!/usr/bin/env bash
# Acceptance for FENCE-DEVNULL-1. RED on HEAD: an unprefixed `> /dev/null` redirect resolves
# its target (the bit-bucket) and is skipped as a non-file write, emptying the target list, so
# FENCE-PARSER-1's "redirect present but no target -> __OPAQUE_BASH__" backstop wrongly fires
# and the command reads as a write (arms the engage-gate; blocked under a focus). GREEN: the
# backstop fires only on a DANGLING redirect (operator with no following target). Every
# FENCE-PARSER-1 write/opaque/bypass guarantee is preserved.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
MOD="$ROOT/hooks/_bash_write_targets.py"
fail(){ echo "FAIL: $*" >&2; exit 1; }
wt(){ printf '%s' "$1" | python3 "$MOD"; }                 # prints targets (one per line) or nothing
is_ro(){ [ -z "$(wt "$1")" ]; }                            # read-only == no targets
is_opaque(){ printf '%s' "$(wt "$1")" | grep -qx '__OPAQUE_BASH__'; }
has_tgt(){ [ -n "$(wt "$1")" ] && ! is_opaque "$1"; }      # enumerated concrete target(s)

# ---- the regression: no-op /dev/null (and friends) must be READ-ONLY ----------------------
for c in \
  'echo hi > /dev/null' \
  'echo hi >> /dev/null' \
  'cmd > /dev/null' \
  'cmd > /dev/stderr' \
  'cmd > /dev/stdout' \
  'some_cmd 2>/dev/null' \
  'build 2>&1' \
  'echo error >&2' ; do
  is_ro "$c" || fail "should be read-only but was not: [$c] -> [$(wt "$c")]"
done

# ---- plain read-only commands stay read-only ----------------------------------------------
for c in 'ls -la' 'grep -r foo src' 'cat file.txt' 'npm install lodash' 'curl https://example.com'; do
  is_ro "$c" || fail "read-only over-blocked: [$c] -> [$(wt "$c")]"
done

# ---- real writes still produce concrete targets -------------------------------------------
has_tgt 'echo hi > out.txt'   || fail "redirect write lost its target"
has_tgt 'cat foo > bar.txt'   || fail "cat redirect lost its target"
has_tgt 'cp a.txt b.txt'      || fail "cp lost its target"
has_tgt 'touch newfile.py'    || fail "touch lost its target"
has_tgt 'rm -rf build'        || fail "rm lost its target"
has_tgt 'mkdir -p x/y'        || fail "mkdir lost its target"
has_tgt 'echo error 2> err.log' || fail "fd-prefixed redirect to a real file lost its target"
has_tgt '&> both.log build'   || fail "&>file (both streams to file) lost its target"

# ---- the `>&word` deprecated redirect-to-file form is a REAL write (security review CRITICAL).
# It must NOT return [] (read-only) — that would slip an out-of-scope write past the live fence.
# Skip ONLY true fd-dups (digit target: >&2). A path target, with or without a space after &,
# is a write to that path.
has_tgt 'echo secret >&/tmp/exfil'   || fail ">&file (no space) slipped as read-only — scope-guard bypass"
has_tgt 'cat x >& /tmp/leak'         || fail ">& file (space) slipped as read-only — scope-guard bypass"
has_tgt 'echo p >&../out'            || fail ">&relpath slipped as read-only — scope-guard bypass"
is_ro   'echo error >&2'             || fail ">&2 (fd-dup) must stay read-only"
is_ro   'echo q >&/dev/null'         || fail ">&/dev/null (both streams to bit-bucket) must be read-only"

# ---- a genuinely DANGLING redirect must stay fail-closed (__OPAQUE_BASH__) ----------------
is_opaque 'cmd >'             || fail "dangling redirect (no target) must stay opaque: [$(wt 'cmd >')]"
is_opaque 'cmd >> '           || fail "dangling append (no target) must stay opaque"

# ---- FENCE-PARSER-1 bypass protections are NOT weakened -----------------------------------
is_opaque 'sed -i s/a/b/ f.ts'             || fail "sed -i must stay opaque"
is_opaque 'ln -s /etc/passwd link'         || fail "ln must stay opaque"
is_opaque 'curl -o out.bin https://x'      || fail "curl -o must stay opaque"
is_opaque 'wget https://x/m.sh'            || fail "wget must stay opaque"
# env/sudo/absolute-path command prefix bypass stays caught (targets enumerated, not empty)
has_tgt 'FOO=bar rm -rf /tmp/x'            || fail "env-prefixed rm bypass regressed"
has_tgt '/bin/rm -rf .harness/canary'      || fail "absolute-path rm bypass regressed"

echo "PASS: > /dev/null (and fd-dup / stderr) is read-only; dangling redirects stay opaque; all FENCE-PARSER-1 write + bypass guarantees preserved"
