# Branch protection (config-as-code)

The merge gate for `main`, kept in-repo so it is reviewable in a PR, not invisible in
GitHub settings. Apply these as a branch protection rule / ruleset on `main`. Until the
ruleset is applied in repo settings, the "blocking" self-review gate is advisory; this
document is the source of truth for what the gate must be.

## Required status checks (must pass before merge)

| Check | Workflow | Why |
|-------|----------|-----|
| `selftest (ubuntu-latest)` | `ci.yml` | the kernel suite passes on Linux (bash 5 / GNU) |
| `selftest (macos-latest)` | `ci.yml` | the kernel suite passes on macOS (bash 3.2 / BSD) |
| `self-review (keyless witnesses)` | `self-review.yml` | the harness reviews its own PR diff; keyless, so it runs on fork PRs |
| `bin/sift end-to-end on a bare shell` | `host-smoke.yml` | the engine drives to confirmed off Claude Code |

`security` (CodeQL, gitleaks) and `benchmark` are advisory (visible, non-blocking).

## Settings

- Require a pull request before merging; require the status checks above.
- Require branches to be up to date before merging.
- Do not allow bypassing the above (no force-push to `main`; no admin override of required
  checks for routine merges).
- Dismiss stale approvals on new commits.

## Applying

GitHub UI: Settings -> Rules -> Rulesets -> new branch ruleset targeting `main`, add the
required checks above. Or via the API / a repo-settings app that reads this file. The
required-check names must match the workflow `name:` fields exactly.
