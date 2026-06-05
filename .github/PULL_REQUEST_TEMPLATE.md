## What this changes

<!-- one line -->

## Proof
- [ ] A RED-first acceptance test exists and is now GREEN
- [ ] `./bin/sift selftest` green
- [ ] Full snapshot sweep green (`for t in evals/snapshots/*/test.sh; do bash "$t"; done`)
- [ ] `bash tests/p8-multihost.sh` + `bash tests/spine-trustcore.sh` green
- [ ] Diff stays inside the packet's `scope.paths`
- [ ] No doc/README claim outlives its implementation

## Notes
<!-- anything reviewers should know; advisory limits stated honestly -->
