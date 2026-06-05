# Contributing to sift

Thanks for looking. sift is a small, dependency-free engine (bash 3.2 + Python stdlib), and it
holds itself to the discipline it sells: every change is proven, not asserted.

## The one rule

**No change lands without a green acceptance test and a clean self-check.** The engine reviews
its own pull requests, `self-review.yml` runs the witness pipeline on the PR diff as a blocking
check, and a claim in a doc that the code does not back is a bug.

## Setup

```bash
git clone https://github.com/baikery-studio/sift.git && cd sift
./bin/sift selftest      # the whole suite, should print "N/N suites green"
```

No install step, no dependencies. If `selftest` is green you have a working tree.

## Making a change

sift is built with sift. Drive your change through the loop:

1. **Scaffold** a packet: `./bin/sift packet new my-change --profile software`
   (or `--paths a,b` / `--from-diff` to seed the scope).
2. **Write a RED acceptance test first** at `evals/snapshots/my-change/test.sh`, it must fail
   before your change and pass after. A marker-grep stub is not a test; `sift doctor` flags it.
3. **Implement the smallest correct diff**, inside the packet's `scope.paths` only.
4. **Run the full sweep before you push**, this is mandatory, later changes have silently
   broken earlier acceptances before:
   ```bash
   bash kernel/sync.sh                              # regenerate the host bundles/adapters
   for t in evals/snapshots/*/test.sh; do bash "$t"; done
   ./bin/sift selftest && bash tests/p8-multihost.sh && bash tests/spine-trustcore.sh
   ```
5. **Keep the diff in scope.** A PR that touches files outside its stated scope will be asked to
   split. Commit messages: conventional (`feat:`/`fix:`/`docs:`), and don't put backticks in
   `git commit -m` (they shell-eval), use `git commit -F file`.

## What gets merged

- Behavioral tests, not structural greps that pass without the feature working.
- Disclosure over assertion: if something is advisory, say so; the threat model lives in
  [`SECURITY.md`](SECURITY.md) and must stay accurate.
- bash 3.2 + macOS/Linux portability (no `${var^^}`, no GNU-only flags). `p8-multihost` is the gate.

## Reporting

- **Security:** see [`SECURITY.md`](SECURITY.md) for the private channel, do not open a public
  issue for a vulnerability.
- **Bugs / ideas:** open an issue with what you ran, what you expected, and what happened.

By contributing you agree your work is licensed under the repository's MIT license.
