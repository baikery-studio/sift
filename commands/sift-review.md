---
description: Review a sift packet (W2/W3/W4 witnesses → witness-bound confirmed)
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift review $ARGUMENTS` from the repo root and report the result. This runs the witnesses and, on success, writes a witness-bound `confirmed` event and clears the scope-guard focus.
