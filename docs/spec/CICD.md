# CI/CD. SOTA Design Spec

## Implementation Status (2026-06-03)

**Built:** `.github/workflows/ci.yml`, `sift selftest` on Linux + macOS (bash 3.2/BSD
portability) + the keyless benchmark; tamper-gate via `verify-log` (no masking). Plus
`.github/workflows/release.yml`, a minimal tag→GitHub Release gated on a green selftest
(both OSes) with tag↔VERSION lockstep. **Planned (NOT implemented):** the fuller
multi-gate pipeline below (blocking self-review, scope-preflight, security/CodeQL,
SLSA/cosign signed releases, scorecard). The 6-gate design below is the target.

---


> Status: DRAFT (canonical for CI/CD). Dated 2026-06-02. The state-of-the-art
> CI/CD design for sift-harness, synthesised from a 4-dimension assessment of
> reference pipelines (claude-code-harness, promptfoo, letta, OpenBB,
> hermes-agent, smolagents). Companion:
> [PLUGIN](./SIFT_HARNESS_PLUGIN.md), [PROFILE_INTERFACE](./PROFILE_INTERFACE.md).
>
> **Scope:** this is the **sift-harness product repo's** CI (the software-profile
> dogfood). It is a per-member pattern, **not** a kernel contract; the family
> kernel does not mandate this exact pipeline. Each future member (e.g. a
> `sift-DoE` repo) instantiates the same pattern with its own profile's witnesses.

---

## 1. Principle: non-hypocritical, then SOTA

The harness enforces RED-first, four independent witnesses, scope enforcement
(default-deny for Write/Edit/MultiEdit/NotebookEdit; a hardened denylist for Bash
mutations with a documented residual gap, per PLUGIN §1),
and rigor-as-CI-exit-code on *every project it governs*. A CI/CD that does not
hold **its own repo** to that same bar is self-refuting. So the first design rule
is **the harness gates its own merges** (§5). Everything else is SOTA hardening
on top of that.

The assessment found the references are individually strong but collectively miss
five things. sift-harness leads on all five (§7).

---

## 2. Pipeline overview

```
PR opened ─┬─ quality        (shellcheck · actionlint · shfmt · ruff · mypy)
           ├─ selftest        (sift selftest · bash-3.2 × BSD/GNU matrix)   [REQUIRED]
           ├─ self-review     (sift review on the PR's own diff; verdict=exit) [REQUIRED]
           ├─ scope-preflight (deterministic, no-API-key; gates FORK PRs)    [REQUIRED]
           ├─ security        (CodeQL · gitleaks · dependency-review · OSV)
           └─ version-sync     (VERSION ↔ plugin.json ↔ marketplace.json drift gate)
                       │
                  merge to main  (branch protection: all REQUIRED checks green)
                       │
tag vX.Y.Z ─── release (CHANGELOG promote · checksums · SLSA provenance · cosign · GitHub Release)
weekly cron ── scorecard (OSSF) · OSV rescan
```

## 3. Required status checks (the merge gate)

Encoded as **config-as-code** (see §6), so the gate is reviewable in-repo, not
buried in GitHub settings:

1. `selftest` (matrix), the generic kernel suite passes on every OS leg.
2. `self-review`, the four-witness verdict on the PR diff is `confirmed`.
3. `scope-preflight`, deterministic scope + RED-first proof check (runs on fork
   PRs that have no secrets).
4. `quality`, lint/format/type gates.
5. `version-sync`, manifests in lockstep (only fires when VERSION-relevant files change).

`security`, `scorecard`, and `benchmark` are advisory (heavy scanners set
`fail-on-severity` conservatively) but visible.

## 4. Workflows

### 4.1 `quality.yml` (PR)
- **shellcheck** on all `*.sh` at `--severity=error` for the curated high-risk
  set, warning-level advisory elsewhere; **actionlint** on workflows; **shfmt**
  format check.
- **ruff** (lint + format) and **mypy** on Python helpers.
- A **portability lint** (the hermes "windows-footguns" pattern, generalised): a
  static check that flags bash-4-only (`declare -A`, `mapfile`, `${v^^}`) and
  GNU-only (`sed -i` without arg, `realpath`, `sha256sum`, `stat -c`) constructs
  so they're caught before the matrix even runs.

### 4.2 `selftest.yml` (PR + push), the cross-OS matrix [REQUIRED]
The #1 gap closed: **run the shell where it breaks.**
```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - { os: ubuntu-latest, shell: bash }          # GNU coreutils, bash 5
      - { os: macos-latest,  shell: /bin/bash }      # bash 3.2, BSD coreutils  <-- load-bearing
      - { os: macos-latest,  shell: bash }           # homebrew bash 5 on BSD coreutils
```
Each leg runs `sift selftest` (the zero-sift-dep generic suite from SH-2.2) and
`sift doctor` self-check. No `|| true`. A non-zero exit is a broken plugin.

### 4.3 `self-review.yml` (PR), the anti-hypocrisy core [REQUIRED]
The harness reviews its own PR. Runs `sift review` on the PR's own diff: the
four witnesses (W1 structural, W2 reproduce, W3 LLM rubric, W4 wiring) execute
and the **witness verdict is the job exit code**. `confirmed` → pass;
`review_failed`/soft-floor-on-a-non-allowed-floor → fail the merge.
- This is claude-code-harness's plugin-self-benchmark and promptfoo's
  `claude-code-review` taken one step further: **blocking, not advisory.**
- W3 runs keyless (deterministic, no model, no network), so CI needs no model backend, no
  API key, and no secrets — the self-review gate works on fork PRs too.

### 4.4 `scope-preflight.yml` (PR, incl. forks) [REQUIRED]
Fork PRs cannot read secrets, so `self-review` (which needs an LLM) cannot gate
them. This deterministic, no-API-key check still does: it runs W1 (state +
acceptance-hash), the scope check (default-deny for the edit tools; the hardened
Bash denylist with its documented residual gap, per PLUGIN §1, no out-of-scope diff), the
RED-first proof-artifact check, and `check-w3-rigor` (no soft-floor laundering).
Forks are gated on the deterministic witnesses; the LLM witness runs post-merge
or on a maintainer re-trigger.

### 4.5 `security.yml` + `scorecard.yml`
- **CodeQL** (python), **gitleaks** (secret scan), **dependency-review** (PR),
  **OSV-Scanner** (PR + weekly), **pip-audit**. Heavy scanners advisory.
- **OSSF Scorecard** (weekly + on default-branch push), badge in README.
- **step-security/harden-runner** on every job with `egress-policy: block` and an
  explicit allowlist (a lead item, no reference does egress control).

### 4.6 `release.yml` (tag `v*`), see §5.

## 5. Release / CD

**Implementation status (2026-06-03, H8-RELEASE):** `release.yml` is now **Built**
(minimal), a `v*` tag whose value matches `VERSION` publishes a GitHub Release via
`gh release create --generate-notes`, with least-privilege `contents: write`. The fuller
pipeline below (CHANGELOG promotion, checksums) is still aspirational, and artifact
**cosign keyless signing + SLSA provenance remain Planned** (not implemented), this
minimal release intentionally ships neither.

**Model:** tag-triggered, `VERSION` as single source of truth. NOT
semantic-release/release-please (those exist to compute-and-publish to a
registry; sift-harness is a git-installed plugin with no PyPI/npm, so they buy
nothing and add a GitHub-App-token dependency).

Pipeline:
1. **Version lockstep** (ported from claude-code-harness, the most mature
   subsystem there): `VERSION` is SSOT → `scripts/sync-version.sh` propagates to
   `.claude-plugin/plugin.json` + `marketplace.json` (every `plugins[].version`)
   → a `.githooks/pre-commit` auto-sync → a CI `version-sync` drift gate that
   fails any PR touching VERSION without syncing manifests + adding a CHANGELOG
   entry.
2. **Tag → release**: a non-cancellable (`cancel-in-progress: false`) workflow
   extracts the CHANGELOG section for release notes and runs a `release-preflight`
   (all required checks green on the tagged SHA).
3. **Artifacts (the prod differentiator the references lack):** a release zip +
   `SHA256SUMS` + **SLSA build provenance** via `actions/attest-build-provenance@v4`
   + **cosign keyless signing** (OIDC, zero key management). claude-code-harness
   ships *unsigned* binaries, this is its single biggest release hole, and we
   close it.
4. **Publish:** GitHub Release via `gh release create` using only the scoped
   `GITHUB_TOKEN` (no registry secret). Marketplace install is git-based, so the
   tag *is* the distribution.

## 6. Supply-chain + governance (config-as-code)

- **Actions SHA-pinned** (not floating `@v4`); `persist-credentials: false`;
  least-privilege `permissions:` per job; `harden-runner` egress block.
- **Dependabot** with a 7-day cooldown (anti fresh-tag-revoke), actions + pip
  ecosystems.
- **CODEOWNERS**, **PR/issue templates**, a **PR-title/commitlint** gate aligned
  to the harness's own `feat:`/`chore:` two-commit protocol.
- **SECURITY.md** (vuln-disclosure policy, mandatory for a tool that runs
  arbitrary acceptance scripts) + **CONTRIBUTING.md**.
- **Branch protection as config-as-code**: the required-checks list and rules
  live in `docs/governance/branch-protection.md` (+ optionally a repo-settings
  app manifest), so the gate is reviewable in PRs, not invisible in settings. No
  reference does this; it's a lead item.

## 7. Where sift-harness leads the field (the five)

1. **Run-everywhere shell matrix** (bash-3.2 × BSD/GNU). References lint shell
   statically and only smoke a compiled binary; we execute the shell on the OS
   that breaks it.
2. **Blocking self-review.** The harness's four-witness verdict gates its own
   merges. promptfoo/claude-code-harness self-review is advisory; ours is required.
3. **Signed + provenanced releases** (cosign keyless + SLSA attestation).
   claude-code-harness ships unsigned; smolagents has no release automation.
4. **Egress-controlled runners** (`harden-runner` block-policy). No reference
   does egress control.
5. **Branch protection as config-as-code.** The merge gate is reviewable in-repo.

## 8. Packet manifest (the CI/CD wave)

Adds a CI/CD wave (new files only, no scope
overlap with the kernel/profile packets). The thin SH-4.4-ci is superseded by
SH-CI.2.

| Packet | Owns | Required-check? |
|---|---|---|
| **SH-CI.1-quality** | `.github/workflows/quality.yml`, `.shellcheckrc`, `ruff.toml`/`pyproject` lint cfg, `.shfmt` | yes (`quality`) |
| **SH-CI.2-selftest-matrix** | `.github/workflows/selftest.yml` (bash-3.2 × BSD/GNU); supersedes SH-4.4-ci | yes (`selftest`) |
| **SH-CI.3-self-review** | `.github/workflows/self-review.yml` + `scope-preflight.yml` (fork-safe) | yes (`self-review`, `scope-preflight`) |
| **SH-CI.4-security** | `codeql.yml`, `security.yml`, `scorecard.yml`, `dependabot.yml`, harden-runner | advisory |
| **SH-CI.5-release** | `release.yml`, `scripts/sync-version.sh`, `check-version-sync`, pre-commit hook, checksums + SLSA + cosign | gate on tag |
| **SH-CI.6-governance** | `CODEOWNERS`, PR/issue templates, commitlint, `SECURITY.md`, `CONTRIBUTING.md`, `docs/governance/branch-protection.md` | yes (`commitlint`) |

Reconciliation: SH-4.3 keeps LICENSE/README/CHANGELOG; **SECURITY.md +
CONTRIBUTING.md move to SH-CI.6** (governance owner) to avoid scope overlap. The
self-review/selftest checks depend on SH-2.2 (`sift selftest`) and SH-1.4
(witness stack) being built first, so the CI/CD wave runs **after** Wave SH-2.
