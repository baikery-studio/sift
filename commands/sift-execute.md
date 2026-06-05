---
description: Execute a sift packet (run acceptance; packeted → acceptance_met)
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift execute $ARGUMENTS` from the repo root and report the result. This runs the packet's acceptance check; on failure the packet goes to `failed` and you should fix and re-execute.
