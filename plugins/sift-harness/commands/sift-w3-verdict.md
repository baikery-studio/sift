---
description: Land an agent-authored host W3 review verdict past the scope fence (sanctioned write verb)
---
Run `SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}" bash ${CLAUDE_PLUGIN_ROOT}/bin/sift w3-verdict $ARGUMENTS` from the repo root, passing the packet id and a staging file holding the host verdict. It snapshots the staging bytes once into a sift-owned location under the reviews dir, validates them against the W3 rubric, and lands the verdict atomically. This is the only sanctioned path for a host-authored verdict to cross the edit-scope fence; it enforces an id charset guard and a size cap.
