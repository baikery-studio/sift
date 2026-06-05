#!/usr/bin/env bash
# Prose profile W4 — SEMANTIC "addresses-the-goal" witness for a writing deliverable.
#
# Same witness SLOT as the software profile's structural anti-dormant W4, a DIFFERENT
# job: here "addresses the goal" means every section the packet declared
# (`artifact.sections: [A, B, C]`) is present in the deliverable. No code-wiring concept
# (import/callsite/route/render) appears here — this is the non-code proof of the
# kernel/profile seam. Fail-closed on any parse/IO error.
set -euo pipefail

# --- stdlib-only frontmatter readers (no PyYAML; fail-closed) ------------------
prose_fm() {  # prose_fm <packet> <scalar-key e.g. artifact.path | goal>
  python3 - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read(); key = sys.argv[2]
m = re.match(r"^---\n(.*?)\n---", text, re.S)
if not m: sys.exit(4)
parts = key.split("."); cur = None; val = None
for line in m.group(1).splitlines():
    mm = re.match(r"^(\s*)([A-Za-z0-9_]+):\s*(.*)$", line)
    if not mm: continue
    ind, k, rest = len(mm.group(1)), mm.group(2), mm.group(3).strip()
    if ind == 0:
        cur = k
        if len(parts) == 1 and k == parts[0]: val = rest
    elif len(parts) == 2 and cur == parts[0] and k == parts[1]: val = rest
if val is None: sys.exit(5)
val = val.strip()
if len(val) >= 2 and val[0] in "\"'" and val[-1] == val[0]: val = val[1:-1]
print(val)
PY
}

prose_sections() {  # prints each declared section, one per line
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.match(r"^---\n(.*?)\n---", text, re.S); body = m.group(1) if m else ""
mm = re.search(r'^\s*sections:\s*\[(.*?)\]', body, re.M)
if mm:
    for s in mm.group(1).split(','):
        s = s.strip().strip('"').strip("'")
        if s: print(s)
PY
}

# --- path containment: reject an artifact.path that escapes the repo root --------
# (mirrors the toy profile — a packet must not satisfy review by pointing at, e.g.,
# /etc/passwd or ../../secret. Resolves through symlinks.)
prose_path_contained() {  # <artifact_path> ; rc 0 if inside repo root
  python3 - "$1" "${SIFT_REPO_ROOT:-$(pwd)}" <<'PY'
import os, sys
art, root = sys.argv[1], sys.argv[2]
base = os.path.realpath(root)
full = os.path.realpath(art if os.path.isabs(art) else os.path.join(base, art))
sys.exit(0 if (full == base or full.startswith(base + os.sep)) else 1)
PY
}

# --- semantic core: are ALL declared sections present in the deliverable? ------
prose_w4_addressed() {  # <artifact-path> <packet-path>
  local artifact="$1" packet="$2"
  prose_path_contained "$artifact" || { echo "artifact.path escapes repo root (traversal rejected)"; return 1; }
  case "$artifact" in /*) ;; *) artifact="${SIFT_REPO_ROOT:-$(pwd)}/$artifact" ;; esac
  [ -f "$artifact" ] || { echo "artifact not found: $artifact"; return 1; }
  local secs sec missing=""
  secs="$(prose_sections "$packet")"
  [ -n "$secs" ] || { echo "packet declares no sections"; return 1; }
  # read line-by-line so a multi-word section ("Executive Summary") is matched whole,
  # not word-split into separate greps (which would false-pass).
  while IFS= read -r sec; do
    [ -n "$sec" ] || continue
    grep -qiF -- "$sec" "$artifact" || missing="$missing; $sec"
  done <<EOF
$secs
EOF
  if [ -n "$missing" ]; then echo "missing required section(s):$missing"; return 2; fi
  return 0
}

witness_w4() {  # witness_w4 <packet_path> <packet_id> <base_sha> <feature_sha>
  local packet_path="${1:-}"
  if [ -z "$packet_path" ] || [ ! -f "$packet_path" ]; then
    printf '{ "ok": false, "reason": "W4 packet not found (fail-closed)" }\n'; return 1
  fi
  local artifact
  artifact="$(prose_fm "$packet_path" artifact.path)" \
    || { printf '{ "ok": false, "reason": "W4 frontmatter parse failed (fail-closed)" }\n'; return 1; }
  local out rc; set +e; out="$(prose_w4_addressed "$artifact" "$packet_path")"; rc=$?; set -e
  if [ "$rc" -eq 0 ]; then
    printf '{ "ok": true, "reason": "all declared sections present — deliverable addresses the goal" }\n'; return 0
  fi
  # JSON-escape the reason (a section name could contain a quote/backslash)
  local rj; rj="$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$out")"
  printf '{ "ok": false, "reason": %s }\n' "$rj"; return 1
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then witness_w4 "$@"; fi
