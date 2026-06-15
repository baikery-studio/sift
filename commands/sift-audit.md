---
description: Second-party replay-verify a confirmed packet in place, or from a portable bundle (--bundle)
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift audit $ARGUMENTS` from the repo root. With a packet id it re-verifies the chain, replays the packet to its terminal, and re-hashes the bound W2/W3/W4 artifacts, printing the grade plus the W2/W3 modes (a degraded label when the reproduce was not a clean checkout). With `--bundle <file.tar>` it does the same from a portable export, deriving the feature SHA from the chain-authenticated terminal event (never the bundle metadata) and checking any signature.
