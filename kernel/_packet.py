#!/usr/bin/env python3
"""Minimal flat-frontmatter field reader (stdlib only — no PyYAML, for H8)."""
import sys, re
if len(sys.argv) < 3:
    sys.exit(0)
path, field = sys.argv[1], sys.argv[2]
try:
    text = open(path).read()
except Exception:
    sys.exit(0)
m = re.search(r'^---\s*\n(.*?)\n---', text, re.S)
fm = m.group(1) if m else ""
for ln in fm.splitlines():
    if ':' in ln:
        k, v = ln.split(':', 1)
        if k.strip() == field:
            print(v.strip().strip('"').strip("'"))
            break
