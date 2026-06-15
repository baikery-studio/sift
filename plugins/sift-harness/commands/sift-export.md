---
description: Write a portable audit bundle (tar) for a confirmed packet, for offline second-party verification
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift export $ARGUMENTS > bundle.tar` from the repo root. The bundle carries the chain-authenticated log prefix plus the packet's review artifacts so another party can replay-verify it with `sift audit --bundle bundle.tar` on a machine that never saw this repo. The exporter refuses a non-terminal packet and drops any path-traversal or symlink members.
