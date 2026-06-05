#!/usr/bin/env bash
# selftest: `sift doctor` flags a confirmed packet whose W3 artifact was deleted.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT; cd "$work"
export SIFT_REPO_ROOT="$work"
"$SIFT" setup >/dev/null; mkdir -p out
cat > tasks/packets/doc.md <<'EOF'
---
id: doc
profile: toy
goal: produce a greeting artifact addressing the goal carrying the marker
artifact:
  path: out/d.txt
  marker: DOC-OK
---
EOF
printf 'a greeting artifact addressing the goal\nDOC-OK\n' > out/d.txt
"$SIFT" plan doc >/dev/null; "$SIFT" execute doc >/dev/null; "$SIFT" review doc >/dev/null
[ "$("$SIFT" state doc)" = confirmed ] || { echo "precondition: doc not confirmed"; exit 1; }
"$SIFT" doctor >/dev/null 2>&1 || { echo "doctor should be clean before deletion"; exit 1; }
rm -f .harness/reviews/doc.w3.json
out="$("$SIFT" doctor 2>&1 || true)"
case "$out" in *doc*) : ;; *) echo "doctor failed to flag missing artifact: $out"; exit 1 ;; esac
"$SIFT" doctor >/dev/null 2>&1 && { echo "doctor must exit non-zero when an artifact is missing"; exit 1; } || true
echo "PASS: sift doctor flags a confirmed packet whose W3 artifact was deleted"
