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
| **your own CLI** | none needed | call `bin/sift` directly |

Driving it anywhere:

```
SIFT_REPO_ROOT="$(pwd)" bash /path/to/sift-harness/bin/sift <verb> [args]
```

## The optional live-steering hooks (Claude Code only)

Under Claude Code, sift wires the full hook lifecycle (the HERD wave). Each event needs a
host hook Claude Code provides; together they herd the agent through the loop at runtime,
on top of the replay-time trust core:

| Event | Adapter | What it does |
|-------|---------|--------------|
| `PreToolUse` | `pretooluse-scope.sh` | scope guard, fences an edit to the focus packet's `scope.paths` (deny = exit 2) |
| `SessionStart` | `sessionstart.sh` | resume adapter, recomputes the wave's resume point from the log into the new context |
| `UserPromptSubmit` | `userprompt-reinject.sh` | re-injects the active-focus contract (packet + next verb + confirmed gate) each prompt, throttled on state-change |
| `Stop` | `stop-block.sh` | blocks ending the turn while the focus packet is planned-but-not-confirmed |
| `PostToolUse` | `posttool-reset.sh` | flags stale acceptance when a scoped file is edited after `acceptance_met` |

These are **host conveniences, not part of the engine**, the trust core works without
them, and dropping them changes nothing about whether a forged `confirmed` is caught (the
log catches it regardless). On hosts without these hooks you lose the live steering but
keep full completion integrity. Under Claude Code the Stop hook makes the turn
un-endable while work is unconfirmed: that is real runtime enforcement, host-honored, not
a kernel sandbox.

## Scope note

Only Claude Code's path is exercised in CI here. The other adapters are the same engine
invoked by path (verified to run from any layout); their host-native install is
operator-attested, not yet observed (`not_observed ≠ absent`).
