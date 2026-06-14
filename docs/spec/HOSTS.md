# Host support

sift-harness is a CLI engine: `bin/sift` + `kernel/` + `profiles/`, bash 3.2 + Python
stdlib, zero dependencies. **If a host can run a shell command, sift runs there**, the
witness-bound trust core (hash-chained log, causal replay, W1–W5 witnesses, the whole
`confirmed`/`partially_confirmed` integrity story) is byte-identical on every host.

There is no per-host configuration and no capability tier to reason about for the core:
the engine is the product, and it's the same everywhere.

## Hosts

Thin adapters (a skill + an `AGENTS.md` pointer, generated from one canonical source by
`sift sync`) let each host discover the workflow. They don't change what the engine does.

| Host | Adapter | How you drive it |
|------|---------|------------------|
| **Claude Code** | `.claude-plugin/` + `hooks/` | `/sift-*` slash commands (or `bin/sift`) |
| **opencode** | `opencode/` | `command/sift-*` + skill (or `bin/sift`) |
| **Cursor** | `.cursor/` + `.cursor-plugin/` | rule + `bin/sift` |
| **Codex CLI** | `.codex-plugin/` + `codex/` | skill + `bin/sift` |
| **Hermes Agent** | `hermes/` | agentskills.io skill + `bin/sift` |
| **Aider** | `adapters/aider/` | `AGENTS.md` standing rule + `bin/sift` |
| **your own CLI** | none needed | call `bin/sift` directly |

Driving it anywhere:

```
SIFT_REPO_ROOT="$(pwd)" bash /path/to/sift-harness/bin/sift <verb> [args]
```

## Observed vs attested

The host-agnostic claim is **observed**, not just attested, for the bare-shell path:
`.github/workflows/host-smoke.yml` drives `bin/sift` end-to-end (setup → plan → execute →
review → `confirmed`) on a plain Ubuntu runner with **no Claude Code, no hooks, no plugin
host**. If that job is green, the trust core demonstrably travels off Claude Code. The
opencode / Codex / Aider / your-own-CLI rows reduce to this same bare-shell drive, so the
bare-shell observation covers them; their thin adapters only change discovery, not the
engine. The Claude Code hook lifecycle below is the part that is Claude-Code-only.

**What travels (every host):** the witness-bound trust core — hash-chained log, causal
replay, `confirmed`/`partially_confirmed` integrity, and `sift audit`. **What is
Claude-Code-only:** the runtime hooks (PreToolUse scope guard, Stop gate); on other hosts
they degrade to guidance while the trust core does not.

## The optional live-steering hooks (Claude Code only)

Under Claude Code, sift wires the full hook lifecycle (the HERD wave). Each event needs a
host hook Claude Code provides; together they herd the agent through the loop at runtime,
on top of the replay-time trust core:

| Event | Adapter | What it does |
|-------|---------|--------------|
| `PreToolUse` | `pretooluse-scope.sh` | scope guard, fences an edit to the focus packet's `scope.paths` (deny = exit 2) |
| `SessionStart` | `sessionstart.sh` | resume adapter, recomputes the wave's resume point from the log into the new context; also exports `SIFT_AGENT_HOST=1` (the explicit agent-host signal, see below) |
| `UserPromptSubmit` | `userprompt-reinject.sh` | re-injects the active-focus contract (packet + next verb + confirmed gate) each prompt, throttled on state-change |
| `Stop` | `stop-block.sh` | blocks ending the turn while the focus packet is planned-but-not-confirmed |
| `PostToolUse` | `posttool-reset.sh` | flags stale acceptance when a scoped file is edited after `acceptance_met` |

These are **host conveniences, not part of the engine**, the trust core works without
them, and dropping them changes nothing about whether a forged `confirmed` is caught (the
log catches it regardless). On hosts without these hooks you lose the live steering but
keep full completion integrity. Under Claude Code the Stop hook makes the turn
un-endable while work is unconfirmed: that is real runtime enforcement, host-honored, not
a kernel sandbox.

## The agent-host signal and the default review regime

`confirmed` certifies a review whose regime depends on whether an agent is present:

- **Under a detected agent host** (the explicit `SIFT_AGENT_HOST=1` the SessionStart hook
  sets), the default W3 validates a host-written R1-R13 rubric verdict the agent lands via
  `sift w3-verdict`, with a rubric-VALUE check (an all-fail rubric under a pass verdict is
  rejected). So a default `confirmed` means "an in-loop reviewer judged this against the
  rubric." Still zero egress: the verdict is authored locally, nothing leaves the machine.
- **Offline / CI** (no `SIFT_AGENT_HOST`), W3 mints a keyless deterministic structural pass,
  so `confirmed` means "structurally reviewed" and the selftest is unchanged.

The signal is the EXPLICIT `SIFT_AGENT_HOST`, never ambient `CLAUDE_PROJECT_DIR` (CI routinely
exports that; keying off it would silently flip CI into requiring a host verdict). Overrides:
`SIFT_W3_REQUIRE_HOST_VERDICT=1` or the profile `require_host_verdict` flag force host mode on;
`SIFT_W3_HOST_VERDICT=off` forces keyless. Propagation caveat: a host where SessionStart
exports do not reach the session shell will not see the signal at review time; on such a host
use the `SIFT_W3_REQUIRE_HOST_VERDICT=1` override (or the profile flag) to get the same default.

## Scope note

Only Claude Code's path is exercised in CI here. The other adapters are the same engine
invoked by path (verified to run from any layout); their host-native install is
operator-attested, not yet observed (`not_observed ≠ absent`).
