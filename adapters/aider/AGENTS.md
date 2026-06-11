# sift-harness — standing rule for Aider

Aider reads `AGENTS.md` (and `CONVENTIONS.md`) as project context. Place this rule in
the repo (or point Aider at it) so an Aider-driven session uses the harness.

## The rule

For any multi-step change, a fix that must be verified, or anything you must not call
"done" prematurely: drive it through sift, not freehand.

Aider has no PreToolUse/Stop hooks, so the live scope guard and the un-endable-turn gate
do **not** apply here. What still holds, fully, is the replay-time trust core: a
`confirmed` is witness-bound, and a forged or hand-edited log replays as `corrupt`.
Completion stays checked, not asserted.

Run the loop with the bare CLI:

```
export SIFT_REPO_ROOT="$(pwd)"
bash /path/to/sift-harness/bin/sift setup
bash /path/to/sift-harness/bin/sift packet new <id> --profile software
# fill the goal, scope.paths, and the acceptance test (evals/snapshots/<id>/test.sh)
bash /path/to/sift-harness/bin/sift plan <id>
# make the change, in scope; produce the deliverable
bash /path/to/sift-harness/bin/sift execute <id>   # acceptance -> acceptance_met
git commit -am "feat: <id>"                          # W2 reproduces from the clean tree
bash /path/to/sift-harness/bin/sift review <id>     # witnesses -> confirmed
bash /path/to/sift-harness/bin/sift state <id>      # confirmed
```

Do not report a task done until `sift state <id>` is `confirmed`.
