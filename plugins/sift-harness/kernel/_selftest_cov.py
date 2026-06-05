#!/usr/bin/env python3
"""Coverage orphan-check: every kernel/profile impl (.sh/.py) must be referenced
from the run graph (kernel/bin/profiles/tests). An impl referenced by nothing is
a coverage orphan. Prints orphan relpaths (one per line); empty = clean."""
import os, sys, glob
root = sys.argv[1]
impl = []
for base in ("kernel", "profiles"):
    for f in glob.glob(os.path.join(root, base, "**", "*"), recursive=True):
        if os.path.isfile(f) and (f.endswith(".sh") or f.endswith(".py")):
            impl.append(f)
corpus = ""
for base in ("kernel", "bin", "profiles", "tests"):
    for f in glob.glob(os.path.join(root, base, "**", "*"), recursive=True):
        if os.path.isfile(f):
            try:
                corpus += open(f, errors="ignore").read()
            except Exception:
                pass
orphans = []
for f in impl:
    name = os.path.basename(f)
    try:
        own = open(f, errors="ignore").read()
    except Exception:
        own = ""
    if (corpus.count(name) - own.count(name)) <= 0:
        orphans.append(os.path.relpath(f, root))
print("\n".join(orphans))
