---
description: Scaffold a new sift packet (sift packet new <id> [--profile toy|software|prose] [--paths a,b | --from-diff])
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift packet new $ARGUMENTS` from the repo root and report the result.

Flags:
- `--profile <toy|software|prose>` — the review profile (default `toy`).
- `--paths a/b.ts,c/d.ts` — seed `scope.paths` with these files (comma-separated) instead of the placeholder.
- `--from-diff` — seed `scope.paths` from the working-tree diff (`git diff`), excluding harness-managed files (`.harness/`, config, packets/snapshots).

After scaffolding, fill in the goal and replace the WEAK placeholder acceptance test with a real check before driving the packet. `sift doctor` flags any packet whose acceptance is still the placeholder.
