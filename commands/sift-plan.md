---
description: Plan a sift packet (submitted → packeted; sets the scope-guard focus)
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift plan $ARGUMENTS` from the repo root and report the result. This pins the packet and makes it the active "focus" — the PreToolUse scope guard will now fence edits to its `scope.paths`.
