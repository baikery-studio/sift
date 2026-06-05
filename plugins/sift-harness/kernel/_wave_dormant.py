#!/usr/bin/env python3
"""W5 R5 dormant-hunt: scan functions DEFINED in the wave's touched files and
flag any not referenced outside their own file (a green-but-dormant def — the
cross-packet 'shipped but unreachable' class). Prints 'file:func' per dormant.
"""
import sys, os, re, glob
root = sys.argv[1]
files = sys.argv[2:]

# Definition forms detected (each may be INDENTED — the \s* prefix):
#   bash:   name() {            function name {            function name() {
#   python: def name(
_DEF_PATTERNS = [
    re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{', re.M),          # bash  name() {
    re.compile(r'^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)', re.M),           # bash  function name
    re.compile(r'^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', re.M),  # python (async) def name(
]


def defs_in(src):
    names = set()
    for pat in _DEF_PATTERNS:
        for m in pat.finditer(src):
            names.add(m.group(1))
    return names


_CSTRIP = re.compile(r"(^|\s)#.*$")
_STRSTRIP = re.compile(r"\"[^\"]*\"|'[^']*'")
# triple-quoted strings span lines -> strip on the whole text (DOTALL) first, else a
# symbol on its own line inside a """...""" docstring survives the per-line pass.
_TRIPLESTRIP = re.compile(r'""".*?"""|\'\'\'.*?\'\'\'', re.S)


def refs(text, name):
    # word-boundary count (so `init` is NOT "referenced" by `reinitialize`), with
    # comments AND string literals stripped — a name appearing only in a comment or
    # a string (`["deadsym"]`, a docstring) is not a real cross-file reference.
    # f-string interiors are stripped too; that fails SAFE (over-flags, never under).
    stripped = "\n".join(_STRSTRIP.sub("", _CSTRIP.sub("", ln)) for ln in _TRIPLESTRIP.sub("", text).splitlines())
    return len(re.findall(r"\b" + re.escape(name) + r"\b", stripped))


corpus = ""
for base in ("kernel", "bin", "profiles", "tests"):
    for f in glob.glob(os.path.join(root, base, "**", "*"), recursive=True):
        if os.path.isfile(f):
            try:
                corpus += open(f, errors="ignore").read()
            except Exception:
                pass

dormant = []
for rel in files:
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        continue
    src = open(p, errors="ignore").read()
    for fn in sorted(defs_in(src)):
        if (refs(corpus, fn) - refs(src, fn)) <= 0:   # never referenced OUTSIDE its own file
            dormant.append("%s:%s" % (rel, fn))
print("\n".join(dormant))
