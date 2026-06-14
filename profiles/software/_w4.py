#!/usr/bin/env python3
"""Software profile W4 — STRUCTURAL wiring witness (anti-dormant).

A shipped symbol must be REACHABLE: it must appear in >= min_hits occurrences
AND across >= 2 distinct files (its definition file + at least one caller). A
symbol defined but never called (a dead def — the "shipped but unreachable" code
agents love to produce) appears in exactly 1 file and is REJECTED.

Reads flat packet keys: wiring_symbol, wiring_min_hits (default 2). Searches
kernel/, bin/, profiles/ under SIFT_REPO_ROOT. Stdlib only.
"""
import sys, os, re, glob, json

pp = sys.argv[1]
root = os.environ.get("SIFT_REPO_ROOT", os.getcwd())


def fm_get(path, key):
    try:
        t = open(path).read()
    except Exception:
        return ""
    m = re.search(r'^---\s*\n(.*?)\n---', t, re.S)
    fm = m.group(1) if m else ""
    for ln in fm.splitlines():
        if ':' in ln:
            k, v = ln.split(':', 1)
            if k.strip() == key:
                return v.strip().strip('"').strip("'")
    return ""


sym = fm_get(pp, "wiring_symbol")
exempt = fm_get(pp, "wiring_exempt").lower() in ("true", "yes", "1")
try:
    min_hits = int(fm_get(pp, "wiring_min_hits") or "2")
except ValueError:
    min_hits = 2

# FAIL CLOSED: a witness that checks nothing must not pass. Exemption is explicit.
if not sym:
    if exempt:
        print(json.dumps({"ok": True, "reason": "wiring_exempt: declared"}))
        sys.exit(0)
    print(json.dumps({"ok": False, "reason": "no wiring_symbol and no wiring_exempt (W4 fail-closed)"}))
    sys.exit(1)


_CSTRIP = re.compile(r"(^|\s)#.*$")
# JS/TS/Go/Java/C# single-line `//` comment. Applied AFTER string stripping (so `http://` inside
# a string is already gone). It can only REMOVE text, so the worst case is dropping a real
# reference after a `//` (e.g. a Python `a // b` floor-division line), which under-counts and
# therefore OVER-flags (blocks) — the documented fail-SAFE bias, never a pass-through.
_JSCOMMENT = re.compile(r"//.*$")
_STRSTRIP = re.compile(r"\"[^\"]*\"|'[^']*'")
# Triple-quoted strings span lines, so they must be stripped from the WHOLE text
# (DOTALL) before the per-line single/double pass — otherwise a dead symbol on its
# own line inside a """...""" block survives and counts as a real reference.
_TRIPLESTRIP = re.compile(r'""".*?"""|\'\'\'.*?\'\'\'', re.S)


# Definition forms (mirrors kernel/_wave_dormant.py _DEF_PATTERNS, the canonical def regex;
# replicated rather than imported because that module reads sys.argv at import time). A line
# matching one of these for `name` DEFINES the symbol — it is not a CALL of it.
_DEF_PATTERNS = [
    re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{'),              # bash  name() {
    re.compile(r'^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\('),  # python (async) def name(
    # JS/TS/Go/Java/C# definition forms (group(1) = the symbol name in every pattern), so a
    # dead `export function`/`const x = () =>`/`class X` is a DEFINITION, not a call. Without
    # these, two definition-only .ts/.go files passed W4 as reachable (the def counted as a
    # call). `function name` here also covers bash `function name` (the leading export/async are
    # optional).
    re.compile(r'^\s*(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)'),  # function name
    re.compile(r'^\s*(?:export\s+(?:default\s+)?)?(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*='),  # const/let/var name =
    re.compile(r'^\s*(?:export\s+(?:default\s+)?)?(?:abstract\s+)?class\s+([A-Za-z_$][A-Za-z0-9_$]*)'),  # class Name
    re.compile(r'^\s*func\s+(?:\([^)]*\)\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*\('),  # go func name( / func (r R) name(
]
# Test-named files / test dirs (mirrors kernel/_signatures.py _TEST_NAME). A reference from a
# test does NOT prove the shipped symbol is reachable in production code.
_TEST_NAME = re.compile(
    r'(^|/)(test_[^/]*|[^/]*_test|[^/]*\.test|[^/]*\.spec|conftest|setup_tests?)\.(py|js|ts|jsx|tsx|go|rb|java|cs)$'
    r'|(^|/)[^/]*Tests?\.cs$'
    r'|(^|/)(tests?|fixtures?|__tests__)/')


def _is_test_file(path):
    return bool(_TEST_NAME.search(path))


def _is_def_line(code, name):
    """Does this (string/comment-stripped) line DEFINE `name`?"""
    for pat in _DEF_PATTERNS:
        m = pat.match(code)
        if m and m.group(1) == name:
            return True
    return False


def _real_refs(text, name):
    r"""Count word-boundary references to `name` that are real code — ignoring
    COMMENT content (a '#' starting a comment at line-start or after whitespace)
    AND STRING LITERALS, including TRIPLE-QUOTED multi-line strings (so neither
    `NAMES = ["deadsym"]` nor a docstring mention is a reference). `\bname\b` means
    `init` is not satisfied by the substring inside `reinitialize`.
    Known limitation: an f-string interior (`f"{name}"`) is stripped too, so a
    symbol referenced ONLY via f-string interpolation may read as dormant — this
    fails SAFE (it can only over-flag/block, never let a dead def through)."""
    pat = re.compile(r"\b" + re.escape(name) + r"\b")
    n = 0
    for ln in _TRIPLESTRIP.sub("", text).splitlines():
        code = _JSCOMMENT.sub("", _STRSTRIP.sub("", _CSTRIP.sub("", ln)))
        n += len(pat.findall(code))
    return n


def _real_calls(text, name):
    """Real CALLS of `name`: word-boundary references on lines that are NOT a definition of
    `name` (a def site is presence, not reachability). On a def line that also references the
    symbol (e.g. a recursive self-call), the def occurrence itself is subtracted so it never
    counts as its own caller. Same comment/string/triple-quote/`//` stripping as _real_refs;
    f-string interiors are stripped too, which fails SAFE (over-flags a dead def).

    Known grep-level limitations (both narrow, neither is the dead-def hole this closes):
      - an import line (`from m import name`) counts as a reference, so a symbol imported but
        never invoked reads as called. Fixing it precisely needs scope analysis; left as-is.
      - a symbol called ONLY recursively inside its own def (no external entry) reads as
        reachable. Distinguishing that needs same-file call-graph analysis. Left as-is.
    The presence floor (>= min_hits across >= 2 files) and the tracked/non-test filters bound
    both cases; they are documented rather than papered over with a fragile heuristic."""
    pat = re.compile(r"\b" + re.escape(name) + r"\b")
    n = 0
    for ln in _TRIPLESTRIP.sub("", text).splitlines():
        code = _JSCOMMENT.sub("", _STRSTRIP.sub("", _CSTRIP.sub("", ln)))
        hits = len(pat.findall(code))
        if hits and _is_def_line(code, name):
            hits -= 1   # the definition occurrence on this line is not a call
        n += hits
    return n


def _w4_search_files(root, packet):
    """The set of files W4 searches for the wiring symbol. Layout-INDEPENDENT:
      1. packet `wiring_paths` (space/comma-separated dirs/globs under root), else
      2. git-tracked files (`git -C root ls-files`) — correct for any layout, and excludes
         build noise / untracked junk, else
      3. (no git) walk root, skipping dot-dirs and common noise.
    .json files are always excluded (manifests, not code)."""
    import subprocess
    _NOISE = {".git", ".harness", ".canary", "node_modules", "vendor", "dist", "build",
              "__pycache__", ".venv", "venv", ".mypy_cache", ".pytest_cache"}
    wp = fm_get(packet, "wiring_paths")
    out = []
    real_root = os.path.realpath(root)

    # The git-tracked set (absolute, realpath'd) for the tracked-only filter. pipeline.sh pins
    # feature_sha with --untracked-files=no, so a caller in an UNTRACKED file would certify a
    # commit that omits it. We intersect wiring_paths globs with this set so untracked callers
    # do not count. Empty (no git / not a repo) => fall back to no filter (last resort).
    def _tracked_set():
        try:
            r = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True, timeout=10)
            if r.returncode == 0:
                return {os.path.realpath(os.path.join(root, p)) for p in r.stdout.splitlines() if p.strip()}
        except Exception:
            pass
        return None

    if wp:
        tracked = _tracked_set()
        for spec in re.split(r"[,\s]+", wp.strip()):
            if not spec:
                continue
            # CONTAINMENT: resolve the spec and skip any that escapes the repo root
            # (../, absolute, or symlink-out). A packet must not direct W4 to search or
            # read outside the repository (matches the toy/prose path-containment guards).
            base = os.path.realpath(os.path.join(root, spec))
            if base != real_root and not base.startswith(real_root + os.sep):
                continue
            if os.path.isfile(base):
                out.append(base)
            else:
                out += [f for f in glob.glob(os.path.join(base, "**", "*"), recursive=True) if os.path.isfile(f)]
        # TRACKED-ONLY: keep only git-tracked files so an untracked caller cannot certify a
        # symbol the pinned feature_sha would not contain. Only filter when git resolved a set;
        # with no git, keep the glob result (last-resort fallback, same bias as the no-git walk).
        if tracked is not None:
            out = [f for f in out if os.path.realpath(f) in tracked]
    else:
        tracked = []
        try:
            r = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True, timeout=10)
            if r.returncode == 0:
                tracked = [ln for ln in r.stdout.splitlines() if ln.strip()]
        except Exception:
            tracked = []
        if tracked:
            out = [os.path.join(root, p) for p in tracked]
        else:
            for dirpath, dirnames, filenames in os.walk(root):
                dirnames[:] = [d for d in dirnames if d not in _NOISE]
                for fn in filenames:
                    out.append(os.path.join(dirpath, fn))
    # Exclude non-code: .json (manifests) and .md (packet declarations + docs). A packet
    # file names its own wiring_symbol, so including it would count the declaration as a
    # code reference and let a dead def pass. W4 searches CODE for the symbol's reachability.
    return [f for f in out if os.path.isfile(f) and not f.endswith((".json", ".md"))]


files, total, calls = [], 0, 0
for f in _w4_search_files(root, pp):
    try:
        text = open(f, errors="ignore").read()
    except Exception:
        continue
    n = _real_refs(text, sym)
    if n > 0:
        files.append(f); total += n
    # A real CALLER is a non-def reference in a NON-test file. A test-only reference does not
    # prove the shipped symbol is reachable in production, so test files never contribute calls.
    if not _is_test_file(f):
        calls += _real_calls(text, sym)
nfiles = len(set(files))
# Reachability, not mere presence: a symbol is wired only if it has >= 1 real caller (a
# non-def, non-test, tracked reference) AND still meets the presence floor (>= min_hits across
# >= 2 files). Two files that only DEFINE it, or a symbol referenced only from tests / only
# from an untracked file, has calls == 0 and is DORMANT. Fail-safe: when in doubt, block.
ok = calls >= 1 and total >= min_hits and nfiles >= 2
if ok:
    reason = "symbol '%s' reachable: %d real call(s), %d occurrences across %d files (>=%d, >=2 files)" % (sym, calls, total, nfiles, min_hits)
else:
    reason = "symbol '%s' DORMANT: %d real call(s), %d occurrences across %d files (need >=1 tracked non-test CALLER and >=%d across >=2 files — a dead def / test-only / untracked-only caller fails)" % (sym, calls, total, nfiles, min_hits)
print(json.dumps({"ok": ok, "reason": reason}))
sys.exit(0 if ok else 1)
