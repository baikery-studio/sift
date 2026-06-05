# Profile Interface. Kernel ⇄ Profile Contract

> Status: DRAFT (canonical). Dated 2026-06-02. The binding contract the
> architecture review found missing: exactly how the task-agnostic kernel loads
> and calls into a task-specific profile. The three shipped profiles (`software`,
> `toy`, `prose`) implement this contract, see each profile's `profile.json` +
> witness scripts under `profiles/<name>/`.

This document is **canonical for**: the domain-neutral state machine, the
profile directory layout, and the four function/data contracts the kernel
depends on. All other specs defer to it.

---

## 0. Glossary (five load-bearing terms)

The set overloads a few words; these are the canonical meanings.

- **packet**, a scoped, hash-pinned unit of work with declared acceptance and
  proof. The atom the harness plans, executes, and reviews.
- **witness**, an independent check that must pass for a packet to reach
  `confirmed`. There are four (W1 structural, W2 reproduce, W3 LLM rubric, W4
  "did it land"); the worker never declares its own completion.
- **wave**, a batch of packets grouped for sequencing in the build plan
  (e.g. SH-1, SH-2, the CI/CD wave); a planning grouping, not a runtime state.
- **profile**, a real per-profile review pipeline (task schema + W3 overlay +
  full W4 impl + acceptance runner/sandbox + soft-floor set) that turns the
  task-agnostic kernel into a harness for one task type (§2–§4).
- **soft-floor**, a declared, named rigor admission (data, not code) that
  caps a verdict at `partially_confirmed`; the kernel rigor checker fails CI
  if a `confirmed` verdict's witness reason matches one (§3.4).
- **W3 review** is keyless: the software W3 renders the rubric + diff into a review
  request and runs a deterministic structural check (a well-formed request carrying a
  diff passes; a malformed one rejects), then writes the fresh W3 artifact. No model
  API, no network, no keys. The verdict parser is injection-resistant (more than one
  embedded verdict fails closed). A `confirmed` under W3 means "structurally reviewed,"
  not "a model judged the code" — the deterministic quartet (W1/W2/scope-guard/W4)
  carries the real weight, and under Claude Code the driving agent is the model that
  reviews the diff.

**A note on `schema_version` (four distinct counters, never one).** Packet
frontmatter carries `schema_version: v1`, the *packet* schema, matching the
live donor. It is **not** the same counter as the manifest's
`manifest_schema_version`, the runtime state's `state_schema_version`, or the
config's `config_schema_version`. The four advance independently; a migration
that bumps one must never be read as bumping another. All packet examples in
this set use `schema_version: v1`.

---

## 1. Canonical state machine (domain-neutral)

The kernel state names are task-agnostic. Software-biased names (`tests_passed`,
`verified`) are gone. These are the only states; profiles do not add states.

**State is derived by causally-validated replay over a hash-chained log, not
last-line-wins.** `project_state` does not simply keep the latest
`metadata.to`. It (1) verifies the log's hash chain (each event carries
`prev_hash` = sha256 of the prior event's canonical JSON), then (2) replays
events ordered by a monotonic per-log `seq` (assigned at append, never wall-
clock `ts`), validating every transition against the table in §1.1. An illegal
or off-table edge, an out-of-order `seq`, or a broken/forged chain is
fail-closed: the derived state is `corrupt` (non-zero exit), never the illegal
target. A hand-appended `confirmed` event therefore breaks the chain and is
detectable, and a `packeted→confirmed` edge does not replay to `confirmed`.
Accurate bound: the chain makes tampering DETECTABLE, not impossible, a
determined operator with write access can still truncate the tail; `sift log
verify`/`repair` surface that loudly. (Mechanics: SH-1.1-primitives builds the
chain + causal replay; SH-1.1b adds the unified validating read policy, `sift
log repair`, and snapshot/compaction.)

| State | Meaning (profile-independent) | Kanban column |
|---|---|---|
| `submitted` | A packet exists, not yet planned | Backlog |
| `packeted` | Validated, hash-pinned, scoped, ready | Planned |
| `executing` | Acceptance running in sandbox (WIP=1) | In Progress |
| `acceptance_met` | Declared acceptance bar passed | In Review |
| `reviewing` | Witnesses are running now | In Review |
| `confirmed` | Independently confirmed by all witnesses | Done |
| `partially_confirmed` | Some witnesses pass, others on a declared soft floor | In Review |
| `failed` | Acceptance failed | Blocked |
| `blocked` | Cannot proceed; needs attention | Blocked |
| `review_failed` | A witness rejected | Blocked |
| `superseded` | Retired by a pivot | (off-board) |

### 1.1 Transitions (each owned by exactly one role)

```
submitted          → packeted              [planner]
packeted           → executing             [executor]
executing          → acceptance_met        [executor]
executing          → failed | blocked      [executor]
acceptance_met     → reviewing             [reviewer]   # on review start
reviewing          → confirmed             [reviewer]
reviewing          → partially_confirmed   [reviewer]
reviewing          → review_failed         [reviewer]
partially_confirmed→ reviewing             [reviewer]
review_failed      → executing             [executor]   # explicit re-execute, NO auto-reset
failed             → executing             [executor]
blocked            → packeted              [planner]    # replan
any                → superseded            [operator]   # emits lane.transition event
```

Two changes from the inherited sift machine, both adopted now (gold standard):
- **`reviewing` is wired live.** `kernel/pipeline.sh` (`sift_review`) emits `acceptance_met→reviewing`
  before running witnesses, and `reviewing→{confirmed,partially_confirmed,
  review_failed}` after. "In Review" then truthfully means *witnesses running*.
- **No `review_failed→acceptance_met` auto-reset.** The inherited "friction
  cleanup" silently promoted rejected packets; removed. Re-entry to the pipeline
  is always an explicit `review_failed→executing` owned by the executor. This
  preserves one-owner-per-transition and an accurate board.
- **`superseded` is reached by an emitted event**, never by reading frontmatter.
  The frontmatter `status: superseded` becomes a consistency assertion only.

---

## 2. Profile directory layout

```
profiles/<name>/
├── profile.json                 # the manifest (schema below)
├── task-schema.json             # JSON-Schema for the profile's frontmatter keys
├── reviewer-prompt.overlay.txt  # W3 rubric overlay (appended to the kernel base)
├── witness_w4.sh                # the profile's W4 implementation (contract §4)
├── acceptance/                  # acceptance runner + sandbox profile assets
│   └── Dockerfile (optional)
└── fixtures/                    # profile-specific tests (opt-in, off by default)
```

### 2.1 `profile.json`

> **Reality (2026-06-03, updated by H5-PROFILE-MANIFEST):** dispatch is **by path convention** (the kernel never reads profile.json's semantic fields at dispatch).
> The kernel resolves `profiles/<name>/` and runs the conventional script
> names (`acceptance/run.sh`, `witness_w3.sh`, `witness_w4.sh`), and at runtime only
> `witness_w3.sh` runs a keyless deterministic check (no backend field). BUT the manifest is no
> longer silently ignored: `sift plan` now **validates `profile.json` at load** against
> the schema below (`kernel/_profile_validate.py`) and **fails closed** if it is malformed
>, required keys + types (`name`, `kernel_version`, `task_schema`, `acceptance`,
> `witnesses`) and `soft_floors` a list. So the schema below is now an **enforced**
> load-time contract (a bad manifest stops dispatch), even though most fields remain
> descriptive rather than behavior-driving.

```jsonc
{
  "name": "software",
  "kernel_version": ">=1.0.0",
  "task_schema": "./task-schema.json",
  "acceptance": {
    "runner": "shell",                 // shell | python | verify
    "sandbox": {
      "image": "sift-sandbox",         // docker image, or null to use env -i
      "interpreter": "bash",
      "network": "none"                // none | fetch (scientist) | compute (doe)
    },
    "plan_pin": "scripts"              // what extended_hash byte-pins: scripts | analysis_plan | source_set
  },
  "witnesses": {
    "w3": { "overlay": "./reviewer-prompt.overlay.txt",
            "model": "claude-opus-4-8", "confidence_floor": 0.7 },
    "w4": { "impl": "./witness_w4.sh" }
  },
  "soft_floors": [
    { "category": "fresh_clone_unavailable",
      "identifying_string": "sandbox env-i, no clone", "applies_to": "w2" }
  ]
}
```

The kernel reads `profile.json` once at load. W1 (structural) and W2 (reproduce)
are kernel-owned and identical across profiles. Only W3 (rubric overlay), W4
(impl), the acceptance runner, the sandbox, and the soft-floor set vary.

---

## 3. Kernel ⇄ profile function contracts

The kernel calls these; each profile provides them. All return structured JSON
on stdout and use exit code 0=ok, non-zero=fail-closed.

### 3.1 Acceptance runner, `acceptance_run`
```
acceptance_run(packet_path, packet_id, sandbox_ctx) -> {
  passed: bool,
  evidence: { ... },        # profile-defined proof payload
  conformance: bool|null    # did the executed work conform to the pinned plan?
}                           # (null when not applicable, e.g. plain test runs)
```
For software, `conformance` is null (tests pass or fail). For sift-DoE,
`conformance` asserts the executed analysis matches the byte-pinned
pre-registered plan. For sift-scientist, it asserts every claim resolved to a
fetched source.

### 3.2 W3 prompt assembly (kernel)
`w3_prompt = read(kernel/reviewer-prompt.base.txt) + read(profile.witnesses.w3.overlay)`
(plain string concatenation; no template engine, no new dependency). The base
contains only domain-neutral review rules; all domain rubric lives in the
overlay.

### 3.3 W4 witness, `witness_w4`
```
witness_w4(packet_path, packet_id, base_sha, feature_sha) -> { ok: bool, reason: string }
```
The kernel owns *only* the call and the fail-closed handling. The entire
implementation (for software: the symbol/wiring anti-dormant heuristics in
`profiles/software/_w4.py`) lives in `profiles/<name>/witness_w4.sh`. **W4 is a full
per-profile implementation.**

The kernel treats `witnesses.w4` (and the profile's judgment witnesses) as
**opaque**: it owns the call and the fail-closed verdict, never the semantics.
The `witnesses.w4` block in `profile.json` is passed verbatim to
`witness_w4.sh`; its internal keys (e.g. software's `code_path_roots` /
`deploy_path_roots`) are profile-private and are **not** validated by the
kernel.

> **W4 is a SLOT, not one job (conceptual-integrity note).** The architecture
> review correctly flagged that W4 means structurally different things across
> profiles: for **software** it is *structural* ("is this code reachable from a
> production callsite?"); for **sift-DoE / sift-scientist / toy** it is *semantic*
> ("does this result/synthesis/artifact answer the question asked?", sometimes an
> LLM call). This is **by design**: W4 is the "did it actually land for *this*
> domain" slot, and "landing" is domain-specific. The kernel guarantees only the
> *contract* (called per packet, fail-closed, verdict feeds `confirmed`), never
> the *semantics*. Do not read "four witnesses" as four fixed algorithms; read it
> as four fixed *questions*, the last two of which the profile answers in its own
> terms. The kernel stays domain-neutral precisely because it never knows what W4
> checks.

### 3.4 Soft-floor rigor, `soft_floors[]` (data, not code)
A profile's `soft_floors[]` declare witness-reason patterns that must cap a verdict at
`partially_confirmed` (never `confirmed`). As built, the witness pipeline enforces this
cap directly, a soft-floored witness lands `partially_confirmed`. (A standalone
`check-w3-rigor` CI gate that scans for these patterns is **Planned. NOT
implemented**; see the SIFT_HARNESS_PLUGIN.md status banner.) Categories are
profile-defined; the mechanism is kernel-owned.

---

## 4. Accurate reuse boundary

Per the architecture review: this is **~60% kernel / ~40% per-profile review
pipeline**. The kernel gives every profile, unchanged:

- the packet model, append-only log, state machine, scope/lane-guard, dispatch
  lock (WIP=1), manifest/reproducibility pinning, W1 (structural), W2
  (reproduce), `sift status`/`doctor` (read-only state surfaces), and the
  rigor/soft-floor *mechanism* (partially_confirmed cap). The kanban projection +
  HTML board are **Planned. NOT implemented** (see SIFT_HARNESS_PLUGIN.md status banner),
  not a kernel-provided feature today.

Each profile must implement:

- its task schema, its W3 rubric overlay, its **full W4 implementation**, its
  acceptance runner + sandbox config, and its soft-floor category set.

This is the gold-standard framing. A new family member is real work (the review
pipeline), not a config file, but the hard, security-critical machinery
(scope, log, state, reproducibility, independent-witness orchestration) is built
once and shared.
