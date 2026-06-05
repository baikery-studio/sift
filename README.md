# sift

**Build-rigor for coding agents. "Done" is something the agent proves, not something it says.**

An agent reports a task complete. The tests never ran, the new function is never called, half the change is missing. It looked successful and was not. The longer the run, the more often this happens, and the model that wrote the code is the worst judge of whether the code is finished.

sift sits between the agent and "done". Work moves through **plan → execute → review** as a hash-pinned **packet**, and a packet reaches `confirmed` only when an append-only, hash-chained log can prove the change was reproduced, reviewed, and wired into the codebase. Skip a step, fake the verdict, or edit the log, and the packet reads `corrupt`. There is no field to set "done" to true.

## Install

**As a Claude Code plugin** (commands + the `sift-workflow` skill + the runtime hooks):

```
/plugin marketplace add baikery-studio/sift
/plugin install sift-harness@sift-harness-marketplace
/reload-plugins
```

Then `/sift-harness:sift-new`, `/sift-harness:sift-plan`, ` ...:sift-execute`, ` ...:sift-review`
are available, and the auto-discovered `sift-workflow` skill drives the loop. Run
`bash ${CLAUDE_PLUGIN_ROOT}/bin/sift init-claudemd` in a repo to make the harness its standing rule.

**As a standalone CLI** (any host, or none, bash 3.2 + Python stdlib, zero dependencies):

```bash
git clone https://github.com/baikery-studio/sift.git
./sift/bin/sift selftest      # verify the install
./sift/bin/sift setup         # bootstrap a repo, then use the Quickstart below
```

## Quickstart

```bash
./bin/sift setup                              # bootstrap .harness/
./bin/sift packet new my-task --profile toy   # a unit of work + its acceptance check
mkdir -p out && printf 'a scaffolded greeting\nmy-task-OK\n' > out/my-task.txt
./bin/sift plan my-task                        # submitted → packeted
./bin/sift execute my-task                     # runs acceptance → acceptance_met
./bin/sift review my-task                      # runs the review witnesses → confirmed
./bin/sift state my-task                       # confirmed
```

The output has to carry the task's marker **and** address its goal, so an agent cannot pass by writing the magic string into an empty file. Try to shortcut the chain (mark a packet confirmed with no real review, or hand-edit the log) and `sift state` returns `corrupt`.

In Claude Code the verbs are namespaced slash commands (`/sift-harness:sift-plan`, `/sift-harness:sift-execute`, `/sift-harness:sift-review`), and a `sift-workflow` skill walks the agent through the loop. The same engine runs on opencode, Cursor, Codex, Hermes, or bare `bin/sift`. Nothing beyond bash and Python. No network, no keys.

## Use it on your repo

The toy profile above is a 60-second smoke test. On a real codebase, use the `software`
profile so "done" means *your tests actually ran*, the rigor lives in the acceptance test
you write, not in a marker:

```bash
./bin/sift packet new add-rate-limit --profile software
# edit tasks/packets/add-rate-limit.md:
#   goal: add a token-bucket rate limiter to the API gateway
#   scope.paths: [src/gateway/ratelimit.ts, src/gateway/index.ts]
# edit evals/snapshots/add-rate-limit/test.sh to run a REAL check, e.g.:
#   npm test -- ratelimit         # the suite must pass  (W2 reproduce)
#   grep -rq 'rateLimit(' src/gateway/index.ts   # the new symbol is actually wired  (W4)
./bin/sift plan add-rate-limit       # fences edits to scope.paths
# ... do the work ...
./bin/sift execute add-rate-limit    # runs your test → acceptance_met
./bin/sift review add-rate-limit     # witnesses → confirmed (or corrupt if faked)
```

A marker-grep acceptance (the toy default) passes on an empty file with the marker, fine for
a smoke test, useless as proof. `sift doctor` flags any packet whose acceptance is still the
unwritten placeholder stub, so a hollow "test" can't quietly bless a `confirmed`.

## Demo

See the whole idea in 30 seconds, in a throwaway dir (no deps, touches nothing):

```bash
bash scripts/demo.sh
```

It reaches a witness-bound `confirmed`, then shows a hand-written "confirmed" replay as `corrupt`, then a tampered log caught by `verify-log`.

## Commands

Lead with the `sift-workflow` skill (the entry point); the commands below are manual step controls for driving one phase by hand.

| Command | Purpose |
|---------|---------|
| `sift packet new\|validate <id>` | scaffold / validate a packet |
| `sift plan\|execute\|review <id>` | drive a packet through the state machine |
| `sift state <id>` · `sift status [wave]` | lane state · read-only summary (focus, next, integrity) |
| `sift next <wave>` · `sift wave-review <wave>` | resume point · system gate over a whole wave |
| `sift focus [<id>\|--clear]` · `sift doctor` | active-packet focus · health check |
| `sift setup` · `sift verify-log` · `sift selftest` | bootstrap · tamper-check the log · run the test suite |

Profiles decide what "reviewed" means: `toy` (smoke test), `software` (code diffs + tests), `prose` (written deliverables). Add one without touching the kernel.

## More

- Security model and what sift does not protect against: [`SECURITY.md`](SECURITY.md)
- Built vs. planned: [`docs/spec/`](docs/spec/SIFT_HARNESS_PLUGIN.md)
- Per-host notes: [`docs/spec/HOSTS.md`](docs/spec/HOSTS.md)

MIT licensed. See [`LICENSE`](LICENSE).
