#!/usr/bin/env bash
# Acceptance for W4-CALLER-1. RED on HEAD: the W4 wiring witness (profiles/software/_w4.py)
# proves TEXTUAL PRESENCE, not REACHABILITY, and globs wiring_paths off the LIVE filesystem
# with no git-tracked filter. So today:
#   (1) two NON-test tracked files that each only DEFINE the symbol (no caller anywhere) pass
#       as 'reachable' — _real_refs counts a definition the same as a call, and the ok-rule is
#       only 'total >= min_hits and nfiles >= 2';
#   (2) the SOLE real caller placed in an UNTRACKED file certifies reachability against a
#       commit that does not contain it — wiring_paths is glob.glob(**/*) with no
#       'git ls-files' intersection (git is only the FALLBACK when wiring_paths is absent).
# GREEN target: require >= 1 reference that is a real CALL (not a definition site, reusing the
# def regex in kernel/_wave_dormant.py) and NOT in a test file (reusing _is_test_file in
# kernel/_signatures.py); and intersect wiring_paths with 'git -C root ls-files' when git is
# available so untracked callers do not count. Fail-SAFE bias preserved (over-flag a dead def).
#
# Drives _w4.py exactly as profiles/software/witness_w4.sh does:
#   python3 _w4.py <packet_path> <packet_id>   (symbol/paths read from packet frontmatter;
#   SIFT_REPO_ROOT is the search root). ok=true => exit 0; dormant => exit 1.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS 2>/dev/null || true

W4PY="$ROOT/profiles/software/_w4.py"
[ -f "$W4PY" ] || fail "scaffold broken: cannot find profiles/software/_w4.py at '$W4PY'"
command -v git >/dev/null 2>&1 || fail "scaffold broken: git is required to prove the tracked-file filter"

# Build an isolated git repo with a packet that pins wiring_symbol + wiring_paths.
# $1 = symbol, then this writes tasks/packets/DEMO.md and inits the repo under $W.
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
SYM="handle_widget"
( set -e
  cd "$W"
  git init -q .
  git config user.email sift@example.invalid
  git config user.name sift
  mkdir -p src tasks/packets
  printf '%s\n' \
    '---' \
    'id: DEMO' \
    "wiring_symbol: $SYM" \
    'wiring_min_hits: 2' \
    'wiring_paths: src' \
    '---' > tasks/packets/DEMO.md
) || fail "scaffold broken: could not init isolated git repo"

w4(){ SIFT_REPO_ROOT="$W" python3 "$W4PY" "$W/tasks/packets/DEMO.md" DEMO 2>/dev/null; }
def_only(){ printf 'def %s(%s):\n    return %s\n' "$SYM" "$1" "$1" > "$2"; }

# ---- 0. PRECONDITION / REGRESSION-GUARD ------------------------------------------------
# A genuine def + a REAL tracked NON-test caller must pass — NOW and after the fix. This is
# the positive control: it guarantees a fix that simply makes every symbol DORMANT (a way to
# 'pass' the two RED cases by breaking reachability for everyone) is itself caught here.
rm -rf "$W/src"; mkdir -p "$W/src"
def_only x "$W/src/a.py"
printf 'from a import %s\n%s(3)\n' "$SYM" "$SYM" > "$W/src/use.py"   # a real caller
( cd "$W" && git add -A && git commit -qm c0 )
w4 | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ok") is True else 1)' \
  || fail "scaffold broken: a genuine def + real tracked caller was rejected by W4 (positive control must pass)"

# ---- 1. DEAD-DEF: two tracked NON-test files that ONLY DEFINE the symbol, NO caller -----
# Word-boundary presence is satisfied (2 occurrences across 2 files) but NOTHING calls it.
# RED today: W4 reports reachable. GREEN: must FAIL (need >= 1 non-def, non-test reference).
rm -rf "$W/src"; mkdir -p "$W/src"
def_only x "$W/src/a.py"
def_only y "$W/src/b.py"
( cd "$W" && git add -A && git commit -qm c1 )
# sanity: both files are tracked and non-test, so the only reason to pass is the def==call bug.
[ "$(cd "$W" && git ls-files src/ | sort | tr '\n' ' ')" = "src/a.py src/b.py " ] \
  || fail "scaffold broken: expected exactly src/a.py + src/b.py tracked"
if w4 | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ok") is True else 1)'; then
  fail "W4 PASSED two def-only files with no caller as 'reachable' (RED: _real_refs counts a definition as a reference; ok-rule is total>=min_hits and nfiles>=2)"
fi

# ---- 2. UNTRACKED CALLER: the sole real caller lives in an UNTRACKED file ---------------
# Defining file is committed; the ONLY caller is an untracked working-tree file. The pinned
# feature_sha would NOT contain it, yet wiring_paths globs the live FS. RED today: reachable.
# GREEN: must FAIL/not-count (intersect wiring_paths with 'git -C root ls-files').
rm -rf "$W/src"; mkdir -p "$W/src"
def_only x "$W/src/a.py"
( cd "$W" && git add -A && git commit -qm c2 )                       # only the DEF is tracked
printf 'from a import %s\n%s(3)\n%s(4)\n' "$SYM" "$SYM" "$SYM" > "$W/src/caller.py"  # UNTRACKED
# sanity: the caller is genuinely untracked (git would not ship it at the feature_sha).
[ "$(cd "$W" && git ls-files src/ | sort | tr '\n' ' ')" = "src/a.py " ] \
  || fail "scaffold broken: caller.py should be UNTRACKED (only src/a.py tracked)"
( cd "$W" && git status --porcelain src/caller.py | grep -q '^??' ) \
  || fail "scaffold broken: src/caller.py is not showing as untracked"
if w4 | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ok") is True else 1)'; then
  fail "W4 PASSED with the sole caller in an UNTRACKED file (RED: wiring_paths globbed off the live FS with no 'git ls-files' intersection — an untracked caller certifies a commit that omits it)"
fi

# ---- 3. POLYGLOT DEAD-DEF: two tracked NON-test JS/TS files that ONLY define the symbol ---
# _DEF_PATTERNS must cover JS/TS (export function / const = / class), not just python+bash,
# or a definition-only .ts file counts its def as a call. Two export-function defs, no caller
# -> must be DORMANT. A `//` comment mention of the symbol must not rescue it either.
JS=handleWidget
cat > "$W/tasks/packets/JS.md" <<EOF
---
id: JS
wiring_symbol: $JS
wiring_min_hits: 2
wiring_paths: src
---
EOF
jsw4(){ SIFT_REPO_ROOT="$W" python3 "$W4PY" "$W/tasks/packets/JS.md" JS 2>/dev/null; }
rm -rf "$W/src"; mkdir -p "$W/src"
printf 'export function %s(x) { return x; }\n' "$JS" > "$W/src/a.ts"
printf 'export function %s(y) { return y; }\n// %s is used somewhere\n' "$JS" "$JS" > "$W/src/b.ts"
( cd "$W" && git add -A && git commit -qm cjs )
if jsw4 | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ok") is True else 1)'; then
  fail "W4 PASSED two JS/TS definition-only files (no caller) as reachable (RED: _DEF_PATTERNS missed JS/TS def forms, so an export-function def counted as a call; a // comment must not count either)"
fi
# a real tracked JS caller makes it reachable again (positive control for the polyglot path).
printf 'import { %s } from "./a";\n%s(3);\n' "$JS" "$JS" > "$W/src/use.ts"
( cd "$W" && git add -A && git commit -qm cjs2 )
jsw4 | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("ok") is True else 1)' \
  || fail "a JS def + real tracked caller was rejected by W4 (polyglot positive control must pass)"

echo "PASS: W4 proves reachability via a real tracked caller (rejects a dead def — python/bash AND js/ts — a test-only reference, and an untracked-only caller)"
