#!/usr/bin/env bash
# selftest: scaffolder + validator reject path-traversal ids/profiles.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
( cd "$work"; SIFT_REPO_ROOT="$work" "$SIFT" setup >/dev/null )
if ( cd "$work"; SIFT_REPO_ROOT="$work" "$SIFT" packet new ".." --profile toy ) >/dev/null 2>&1; then echo "id .. not rejected"; exit 1; fi
[ -e "$work/evals/test.sh" ] && { echo "id .. escaped snapshots"; exit 1; } || true
cat > "$work/tasks/packets/t.md" <<'PK'
---
schema_version: v1
id: t
profile: ../kernel
goal: x
proof_artifact: {path: evals/snapshots/t/proof.json, required_terminal_event: t.x}
scope:
  type: harness
  paths: [out/x]
---
PK
if ( cd "$work"; SIFT_REPO_ROOT="$work" "$SIFT" packet validate t ) >/dev/null 2>&1; then echo "profile ../kernel not rejected"; exit 1; fi
echo "PASS: scaffolder + validator reject path-traversal ids/profiles"
