# sift-harness Plugin. Product Spec (v1)

## Implementation Status (2026-06-03)

**Built:** `bin/sift` (plan/execute/review/state/verify-log/selftest/setup/
wave-review/next/doctor/focus/`packet new`/`packet validate`), the kernel
(hash-chained log, causal replay, witness binding), toy + software profiles,
hooks/sessionstart adapter, CI, benchmark, the `sift packet new` scaffolder, and
sift's own packet validator (`sift packet validate`, sift packets are a distinct
schema from the donor's, so sift validates its own).
**Built (Phase 2, advisory):** the PreToolUse scope guard, `hooks/pretooluse-scope.sh`
blocks an edit outside the active ("focus") packet's `scope.paths`. Advisory: it
protects only when the host is wired to run the hook (it is not a kernel sandbox).
**Built (Phase 2):** `.claude-plugin/plugin.json` + `marketplace.json` packaging,
the `/sift-*` slash-command surface (`commands/`), `hooks/hooks.json` (wires the
scope guard + resume adapter via `${CLAUDE_PLUGIN_ROOT}` so install = protected),
`README.md` quickstart, and `LICENSE`. The plugin is **plugin-validator PASS
(installable, 0 critical)** and the engine is proven RELOCATABLE by a smoke test
(see `docs/INSTALL_VERIFICATION.md`). The one remaining step, a live interactive
`/plugin install` in a CC session, is operator-run and logged as not-yet-observed,
not asserted green (this context can't drive interactive slash commands).
**Built:** W3 review is keyless, a deterministic structural check (a well-formed review
request carrying a diff passes; a malformed one rejects). No model API, no network, no
keys, no data egress. A `confirmed` under W3 means "structurally reviewed," not "a model
judged the code." Under Claude Code the driving agent is itself the model that reviews
the diff.
**Built (Phase 5):** the `skills/` surface, `skills/sift-workflow/SKILL.md`
(auto-discovered; `skills` is not a manifest field) teaches an agent the
plan→execute→review loop on rigor-warranting tasks. A command/skill-consistency
test guarantees it only references real `bin/sift` verbs (anti-drift). Note: a
skill is read-and-follow **guidance, not enforcement**, the witnesses, witness-
binding, scope guard, and log are the enforcement; the skill only makes them
discoverable.
**Planned (NOT implemented):** the soft-floor checker that fails CI, and the HTML kanban board (`/sift-board`), neither exists in the kernel.
Also Planned: a live interactive `/plugin install` run (operator step, checklist in
`docs/INSTALL_VERIFICATION.md`).

---


> Design spec (see the §0 Implementation Status banner above for Built-vs-Planned).
> sift is `sift/harness` extracted into a standalone, installable Claude Code plugin,
> hardened to the standard set by `claude-code-harness`. An HTML kanban board is Planned
> (NOT implemented).

---

## 1. What v1 is

A Claude Code plugin that installs the Sift plan→execute→review harness into any
repository. After install and `/sift-setup`, the host repo gains:

- a scoped, fail-closed `plan → execute → review` pipeline whose unit of work is
  a **packet**,
- a PreToolUse scope guard: **default-deny for Write/Edit/MultiEdit/NotebookEdit**
  (denied outside the active packet's declared scope; `.harness/`/`.canary/` denied
  to edit tools entirely). The scope guard governs **edit tools only**, it does NOT
  inspect Bash. A separate, declarative `.claude-plugin/settings.json` deny layer
  blocks a named set of destructive/secret/egress Bash commands (advisory host
  permissions), but arbitrary Bash is **not** sandboxed (see SECURITY.md, the
  unsandboxed-host / tamper-evident ceiling),
- a four-witness review gate whose **worker-independent** guarantees are the
  deterministic quartet (W1 hash-pin over a hash-chained causal log, W2
  reproduce, scope-guard, W4 wiring); W3 is a keyless deterministic structural check,
  not headlined as independence,
- a generated, drift-proof **HTML kanban board** that visualises every packet's
  real state *(Planned. NOT implemented)*,
- the partially_confirmed floor discipline (the soft-floor *checker* that fails CI is
  *Planned. NOT implemented*; the status banners, proof.json, and SPEC_DRIFT
  reconciliation are what's real today).

v1 ships three profiles, **`software`** (keyless deterministic review), **`toy`** (keyless
deterministic), and **`prose`** (a non-code writing-deliverable profile that proves the
seam at N>2), and the kernel/profile seam is
real in code (`kernel/` + `profiles/software/`) so `sift-DoE` and
`sift-scientist` can slot in later without a rewrite.

---

## 2. What v1 is NOT

- Not a Go rewrite. The engine stays Bash + Python (it runs on 60+ real packets).
  Go is a roadmap item, recorded with the host-dependency note with the host-dependency note below.
- Not multi-host. Claude Code only. No Codex/Cursor/OpenCode adapters in v1.
- Not adaptive orchestration. Single dispatch lock, WIP=1.
- Not a publisher of unproven support claims. Tiers are accurate (§8).

---

## 3. Install and lifecycle

```bash
# install (local/private marketplace in v1; public optional later)
/plugin marketplace add ./sift-harness          # or a GitHub repo
/plugin install sift-harness@sift-harness-marketplace
/sift-setup                                      # bootstraps repo-side state

# the loop
/sift-plan    <packet-id>    # validate, hash-pin, write plan, set focus
/sift-execute <packet-id>    # RED-first acceptance, manifest (verb is `execute`)
/sift-review  <packet-id>    # four witnesses, fail-closed
/sift-status  [wave]         # read-only: focus / next / log integrity / doctor
/sift-board                  # (Planned. NOT implemented) HTML kanban
/sift-doctor  <packet-id>    # read-only: state / blocker / next command
```

`/sift-setup` is the bootstrap boundary. The **plugin** ships the engine
(installs globally into `~/.claude/plugins/`); the **host repo** holds runtime
state (`.harness/`, `tasks/packets/`, the generated board), created by setup.

---

## 4. Architecture: plugin vs repo

Real layout as built (2026-06-03, the original design tree this section once
showed has been replaced with what actually ships):

```
PLUGIN (the repo / installed plugin root)
├── .claude-plugin/{plugin,marketplace}.json
├── hooks/{hooks.json, pretooluse-scope.sh, sessionstart.sh}
├── bin/sift                      # dispatch shim (fail-soft), verbs below
├── kernel/                       # task-agnostic engine (bash + stdlib python)
│   ├── _log.py _state.py _scope.py _validate.py _wave_dormant.py
│   │   _selftest_cov.py _packet.py                 # stdlib python helpers
│   ├── config.sh log.sh state.sh lock.sh packet.sh pipeline.sh manifest.sh
│   ├── selftest.sh setup.sh wave.sh next.sh scaffold.sh scope_guard.sh doctor.sh
│   └── reviewer-prompt.base.txt
├── profiles/{toy,software}/      # software: witness_w3.sh, _w4.py, acceptance/run.sh
├── commands/sift-*.md            # /sift-plan|execute|review|next|doctor|new
├── skills/sift-workflow/SKILL.md # auto-discovered
├── tests/  benchmarks/  evals/snapshots/  docs/  README.md  LICENSE  VERSION

HOST REPO (the operator's repo; sift setup bootstraps .harness/)
├── tasks/packets/<ID>.md         # packets
├── .harness/{focus,log.jsonl,reviews/,runs/,waves/}
└── sift-harness.config.json
```

> NOTE: the original design's extra components, a board-generator dir, a
> soft-floor checker dir, separate review / reviewer / wiring-witness
> scripts, a sandbox helper, and a python manifest, were never built; only the
> files listed above ship. The HTML board and the soft-floor checker are
> **Planned (NOT implemented)** (see the status banner).
```

---

## 5. The dispatch shim (`bin/sift`)

Copied in spirit from `claude-code-harness/bin/harness`:

1. Resolve through symlinks to the plugin root.
2. Route by subcommand: `plan|execute|review|state|status|verify-log|selftest|setup|wave-review|next|doctor|focus|packet|version` (`board` is Planned).
   v1 maps each to the existing shell scripts under `kernel/` and
   `profiles/software/`.
3. **Fail-soft:** on any missing dependency or unresolved plugin root, log to
   stderr and exit 0 with empty stdout. A broken install is a no-op, never a
   session-halting error.

As built, `hooks/hooks.json` wires the host hooks directly to the scripts via
`${CLAUDE_PLUGIN_ROOT}`: PreToolUse → `hooks/pretooluse-scope.sh`, SessionStart →
`hooks/sessionstart.sh`. Each hook script resolves the repo root via
`$CLAUDE_PROJECT_DIR` (then `$SIFT_REPO_ROOT`, then `$PWD`) and calls `bin/sift`
subcommands. (There is no `bin/sift hook <event>` dispatcher, the host invokes the
hook scripts directly.)

---

## 6. Configuration (`sift-harness.config.json`)

A small, safe-by-default JSON config, JSON-Schema validated. Replaces the
hard-coded paths the agent review found baked into the scripts.

```jsonc
{
  "safety": { "mode": "apply-local", "max_auto_retries": 2 },   // dry-run|apply-local|apply-and-push
  "git":    { "protected_branches": ["main", "master"], "auto_push": false },
  "paths": {
    "packets":   "tasks/packets",        // was hard-coded
    "snapshots": "evals/snapshots",      // was hard-coded
    "state":     ".harness",
    "canary":    ".canary",
    "board":     ".sift/board.html"
  },
  "acceptance": { "runner": "shell", "sandbox": "docker-or-env-i" },
  "profile": "software"
}
```

Every path the kernel currently assumes (`tasks/packets/`, `evals/snapshots/`,
`.harness/`, `.canary/`) is read from here. The W4 `services|packages|frontend/src`
assumption moves into `profiles/software/profile.json`, not the kernel.

---

## 7. Decoupling work (HISTORICAL, extraction is complete)

> **Historical.** This section recorded the original plan to extract the harness from
> its donor codebase. That extraction is **done**, the engine lives in `kernel/` +
> `profiles/` with config-driven paths, a plain-shell self-test (`sift selftest`, no
> `npm`), and the software-specific review rules in the software profile's overlay
> (not the kernel base). The script names listed in early drafts (`lane-guard.sh`,
> `check-w3-floor.sh`, `canary-update.sh`, …) were never ported under those names;
> the shipped equivalents are `hooks/pretooluse-scope.sh` (scope guard) and the
> witness pipeline's `partially_confirmed` soft-floor cap (rigor). See the §0
> status banner for what is Built vs Planned.

---

## 8. Support tiers (carried from the kernel)

- The plugin states its **host dependency** plainly: requires `bash` and
  `python3` on the host. This is the cost of not being Go-native; it is
  documented, not hidden (`not_observed != absent`).
- The soft-floor discipline ships partially: W2 degrades to `env -i` when Docker is
  absent and says so, and a soft-floored witness lands as `partially_confirmed` (never
  `confirmed`). The standalone `check-w3-floor.sh` CI gate is **Planned. NOT
  implemented** (no such script exists in the kernel; see the §0 status banner). The
  partially_confirmed cap is enforced by the witness pipeline, not by a separate checker.
- **Documentation-drift fix is part of v1.** The extraction reconciles the
  inherited `HARNESS.md` banner with the live code (W3 wired, W4 exists,
  opus-4-8, R1..R12), closes the PyYAML/stdlib inconsistency (H8), and aligns
  the `scope_paths` vs `scope.paths` field-name divergence. We extract from an
  accurate baseline.

---

## 9. Acceptance bar for v1 (the harness's own DoD)

v1 is done when, on a **fresh clone of a throwaway target repo** with the plugin
installed:

1. `/sift-setup` bootstraps repo-side state with no operator-resident files (H8).
2. A trivial fixture packet runs `plan → execute → review` to a real `confirmed`
   verdict, with all four witnesses recorded with the host-dependency note.
3. The PreToolUse guard denies a write outside the active packet's scope (proven
   by fixture), and allows one inside it.
4. *(Planned. NOT implemented)* `/sift-board` generates an HTML board whose
   columns match `state.sh project_state` for every packet, and a hand-edit to the
   board is ignored or flagged (generated, not authoritative-by-hand).
5. The generic kernel self-test passes with zero sift-specific dependencies
   (no `npm`, no `services/`, no tenancy fixtures).
6. The docs match the code (the standalone `check-w3-floor.sh` gate is Planned, the
   partially_confirmed floor discipline is enforced by the witness pipeline's partially_confirmed cap).

Each criterion is paired with a fixture under `tests/`, per the harness's own
"every claim has a fixture" rule.
