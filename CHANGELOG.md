# Changelog

All notable changes to sift. Format loosely follows [Keep a Changelog](https://keepachangelog.com);
this project versions in lockstep with the `VERSION` file (a `vX.Y.Z` tag must match it to release).

## [0.4.0], 2026-06-15

The "decisions above the core, and a second party can check it" release. Added an orchestration
layer that drives and explains a wave without ever being able to move a packet, portable audits a
third party can replay, and opt-in signed verdicts, then drove the whole thing through the harness
on itself.

### Added
- **Orchestration (ORCH wave):** `sift drive <wave>` autonomously loops a wave plan->execute->review
  to ALL-CONFIRMED under a single-writer lock; coverage-fed append-only replanning scaffolds a
  covering packet for each uncovered requirement; an economic governor halts a packet at its retry
  ceiling (counted from the verified chain, never a side-counter). Every choice is recorded as an
  `orch.*` event that is chained and ordered yet inert to state projection, so the orchestrator can
  never confirm, corrupt, or move a packet. `sift trace <wave>` reads those decisions back.
- **Portable audit (`sift export` / `sift audit --bundle`):** write a tar bundle (chain-authenticated
  log prefix plus review artifacts) that a second party can replay-verify on a machine that never
  saw the repo. Provenance derives from the chain terminal, not bundle metadata; tar members are
  sanitized against path traversal, symlinks, and duplicates.
- **Signed verdicts (opt-in):** `sift review --sign` attests a verdict with a local ssh key
  (`ssh-keygen -Y`, zero network); the signer public key is recorded inside the chained verdict
  event so the hash covers identity. Keyless remains the default.
- **W3 semantic teeth:** `sift w3-verdict <id> <staging>` lands an agent-authored host verdict past
  the scope fence through a snapshot-once-then-validate path; a rubric-VALUE check with a closed
  pass/fail token allowlist; host-verdict mode gated on explicit `SIFT_AGENT_HOST=1` so CI stays
  keyless. `sift audit` surfaces the W3 mode.
- **Data-driven witnesses:** the witness set is read from the profile, so a profile can declare an
  extra witness; the mandatory software set stays w2/w3/w4 byte-identical.
- **Slash commands** for the new verbs (`drive`, `export`, `trace`, `w3-verdict`, `audit`) so every
  host adapter surfaces them.

### Changed
- **W2 reproduces from a worktree** of the feature SHA (with a test-path containment guard) instead
  of in place, so the acceptance oracle is verified against a clean tree.
- **Scale:** single-pass state verification with an in-process memo keyed on file identity
  (ino + ctime + mtime + size), plus a `--batch` projector; per-packet artifact re-hash is never
  skipped.

### Fixed
- **Bash write-fence:** `> /dev/null` and `>&word` redirects no longer read as opaque scope-fence
  bypasses; the `>&word` form is parsed at the finditer.
- **Anti-tamper review** re-scans changed files per commit (SHA-namespaced) so an add-then-delete or
  single-commit sandwich cannot slip a tampered file past review.
- **CI ran a hollow suite:** the acceptance oracles the durable `tests/` suite delegates to were
  gitignored, so a fresh clone (CI) skipped them; they now ship, and the mirror anti-drift check
  ignores transient bytecode.
- **Soft-floor completion:** a `partially_confirmed` member now counts as done for `sift next` and
  wave-review, so a soft-floored packet can actually ship.

## [0.3.0], 2026-06-04

The "make it actually herd, and prove it" release. Took the plugin from a strong engine in a weak
product to runtime-enforced discipline, driven through the harness on itself.

### Added
- **Runtime herding hooks (HERD wave):** Stop block (turn can't end while a packet is unconfirmed),
  UserPromptSubmit re-injection of the active-focus contract, PostToolUse stale-acceptance reset, 
  alongside the existing PreToolUse scope guard and SessionStart resume.
- **Engage-gate (FORT-1 + FORT-5):** a freehand edit with no active packet, via the Edit/Write
  tools *or* a Bash file-write (redirects, `tee/cp/mv/touch/sed -i/perl -i/-e/curl -o`, …), arms a
  marker so the Stop hook refuses to end the turn until the work is packeted or cleared. Read-only
  shell sessions are untouched.
- **SessionStart standing primer** in sift-set-up repos (silent elsewhere); `sift init-claudemd`
  writes an idempotent "use the harness" standing rule into `CLAUDE.md`.
- **DX:** `sift packet new --paths a,b` / `--from-diff` seed `scope.paths` (excluding harness
  noise); `sift doctor` flags unwritten placeholder acceptances; the `sift-workflow` skill is the
  framed entry point.
- **Evidence (PROVE):** a benchmark measuring the engage-gate (freehand-bail escape 100%→0%), and a
  CI-verified host-contract proof (`PRV-3`) that a Stop-honoring host refuses a premature end and
  releases only at `confirmed`.

### Changed
- **Dropped the replay checkpoint (HD2-1):** measured ~1.4× (not load-bearing) and forgeable by any
  operator who can write files; `project_state` now always verifies the full chain, no integrity
  bypass cheaper than rewriting a fully-valid chain.
- Atomic `mv`-steal stale-lock reclaim (HD2-2); `sift focus --clear` now also releases the
  engage-gate.
- README reframed as a build-rigor harness; namespaced `/sift-harness:sift-*` command references.

### Removed
- **Network W3 egress.** W3 review is now keyless-only: a deterministic structural
  check with no model API, no keys, and no network. sift makes no network calls. Removed the
  consent gate, secret-redaction module, network backends, and the egress audit log. Under
  Claude Code the driving agent is already the model, so a separate cloud reviewer was redundant.

### Fixed
- Claude Code plugin **load failure**, `hooks/hooks.json` must be a `{"hooks": {...}}` record and
  the manifest must not declare auto-discovered `commands`/`hooks`.
- Independent-review findings: a `focus --clear` wedge, Bash-heuristic false-positives/negatives, a
  broken snapshot path, and doc overclaims.

## [0.2.0], 2026-06-03

Installable Claude Code plugin: runtime scope guard, `sift packet new` scaffolder + validator,
host-agnostic W3 backend registry, egress governance (redaction + consent + audit log), the
`sift-workflow` skill, a declarative deny layer, a static test-tampering gate, and a third
(`prose`) profile proving the kernel/profile seam at N>2. Published to
`github.com/baikery-studio/sift`.

## [0.1.0], 2026-06-02

Spine: the hash-chained, causally-replayed, witness-bound trust core (`bin/sift` +
plan→execute→review→`confirmed`), the `toy` profile, and the self-hosting threshold (the harness
builds and judges itself).

[0.4.0]: https://github.com/baikery-studio/sift/releases/tag/v0.4.0
[0.3.0]: https://github.com/baikery-studio/sift/releases/tag/v0.3.0
[0.2.0]: https://github.com/baikery-studio/sift/releases/tag/v0.2.0
[0.1.0]: https://github.com/baikery-studio/sift/releases/tag/v0.1.0
