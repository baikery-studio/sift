# Changelog

All notable changes to sift. Format loosely follows [Keep a Changelog](https://keepachangelog.com);
this project versions in lockstep with the `VERSION` file (a `vX.Y.Z` tag must match it to release).

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

[0.3.0]: https://github.com/baikery-studio/sift/releases/tag/v0.3.0
[0.2.0]: https://github.com/baikery-studio/sift/releases/tag/v0.2.0
[0.1.0]: https://github.com/baikery-studio/sift/releases/tag/v0.1.0
