---
description: Health-check the harness state (flags confirmed packets with a missing W3 artifact)
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift doctor` from the repo root and report any problems. Non-zero exit means a confirmed packet's load-bearing W3 artifact is missing.
