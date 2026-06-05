---
description: Show the next actionable packet in a wave (compaction-survival resume)
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift next $ARGUMENTS` from the repo root and report which packet to work next. State is recomputed from the log, so this is correct even after a context compaction.
