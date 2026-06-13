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
_STRSTRIP = re.compile(r"\"[^\"]*\"|'[^']*'")
# Triple-quoted strings span lines, so they must be stripped from the WHOLE text
# (DOTALL) before the per-line single/double pass — otherwise a dead symbol on its
# own line inside a """...""" block survives and counts as a real reference.
_TRIPLESTRIP = re.compile(r'""".*?"""|\'\'\'.*?\'\'\'', re.S)


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
        code = _STRSTRIP.sub("", _CSTRIP.sub("", ln))
        n += len(pat.findall(code))
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
    if wp:
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


files, total = [], 0
for f in _w4_search_files(root, pp):
    try:
        n = _real_refs(open(f, errors="ignore").read(), sym)
    except Exception:
        n = 0
    if n > 0:
        files.append(f); total += n
nfiles = len(set(files))
ok = total >= min_hits and nfiles >= 2
if ok:
    reason = "symbol '%s' reachable: %d occurrences across %d files (>=%d, >=2 files)" % (sym, total, nfiles, min_hits)
else:
    reason = "symbol '%s' DORMANT: %d occurrences across %d files (need >=%d and >=2 files — a def with no caller fails)" % (sym, total, nfiles, min_hits)
print(json.dumps({"ok": ok, "reason": reason}))
sys.exit(0 if ok else 1)
