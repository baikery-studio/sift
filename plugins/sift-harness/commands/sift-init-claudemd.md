---
description: Write a sift "use the harness" standing rule into the repo's CLAUDE.md (hard-law, idempotent)
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift init-claudemd` from the repo root. This appends a fenced, idempotent standing-rule block to CLAUDE.md so the harness is treated as the law of this repo (a user instruction outranks the SessionStart primer). Safe to re-run.
