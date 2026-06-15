---
description: Show the orchestrator's decisions for a wave (WHY each step was chosen), read from the verified log
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift trace $ARGUMENTS` from the repo root. It reads the tamper-evident log and prints, in chain order, the `orch.*` decisions scoped to that wave (dispatch choices, coverage gaps, governor halts). The orchestrator's record rides the same chain as the witnesses but is inert to state projection, so it can never move a packet. If the chain does not verify it warns the trace is from a tampered log.
