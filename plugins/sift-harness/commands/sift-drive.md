---
description: Autonomously loop a wave plan→execute→review until every member is witness-bound (ALL-CONFIRMED)
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift drive $ARGUMENTS` from the repo root. The driver dispatches the wave's next actionable packet each iteration under a single-writer lock, records each choice as an inert `orch.decision` event, and stops at ALL-CONFIRMED (or when the economic governor halts a packet that hit its retry ceiling). State is replayed from the log, so a fresh process resumes correctly after a compaction.
