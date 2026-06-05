# Install Verification (Phase 3, criterion 4)

This records how far "installable" has actually been verified, and where the
limit is. Per the project's discipline: **not_observed ≠ absent**. We do not
claim a green live install we didn't watch.

## What was verified, plugin-validator: PASS (installable)

The purpose-built **`plugin-dev:plugin-validator`** was run against this plugin
(2026-06-03). Verdict: **PASS, installable, 0 critical issues.** Specifics it
confirmed:

- `.claude-plugin/plugin.json`, valid JSON, required `name` (kebab-case), valid
  semver `version`, plus `description`/`author`/`license`/`keywords`/`commands`/
  `hooks`. `/plugin install` will accept it.
- `.claude-plugin/marketplace.json`, valid; `source: "."` resolves to the repo root.
- `commands/sift-*.md`, 6 commands, all valid frontmatter + body; register as
  `/sift-doctor|execute|new|next|plan|review`; each uses `${CLAUDE_PLUGIN_ROOT}/bin/sift`.
- `hooks/hooks.json`, `PreToolUse` (matcher `Edit|Write|MultiEdit|NotebookEdit`) and
  `SessionStart`, both `type: command` via `${CLAUDE_PLUGIN_ROOT}`; both referenced
  scripts exist, are executable, and have `#!/usr/bin/env bash`, they will fire.

**Warnings the validator raised, and disposition:**

| Warning | Disposition |
|---------|-------------|
| `VERSION` (`0.1.0-spine`) ≠ manifest (`0.2.0`) | **Fixed**, `VERSION` bumped to `0.2.0` so `bin/sift version` and the manifest agree. |
| SessionStart `"matcher": "*"` (ignored for lifecycle events) | **Fixed**, `matcher` dropped from the SessionStart entry. |
| No `author` field (best practice) | **Fixed**, `author` added to `plugin.json`. |
| Redundant explicit `commands`/`hooks` keys (= defaults) | Left as-is, explicit and correct; harmless. |
| `$CLAUDE_PROJECT_DIR` in the hook scripts | **Not a defect (corrected note).** Earlier flagged in error, it is correct: the hooks resolve the user's **repo root** via this variable, which is *different* from `CLAUDE_PLUGIN_ROOT` (the install dir `hooks.json` uses to locate the scripts). Both are right; nothing to change. |

Combined with the Phase-2 relocatability smoke test (a copied engine drives a
packet to `confirmed`), the structural + relocatable bar is **verified**.

## What is NOT verified here

A live, interactive **`/plugin install`** in a running Claude Code session **cannot
be driven from this non-interactive build context**, slash commands are an
interactive surface, not something this harness can invoke and observe. So:

- "Installable" = **structurally valid (plugin-validator PASS) + relocatable
  (smoke test) + manual-checklist-provided.**
- It is **not** "a maintainer ran `/plugin install` and watched the commands/hooks
  register live." That step is **operator-run** (below), and is logged as not-yet-
  observed rather than asserted green.

## Manual `/plugin install` checklist (operator-run, ~2 min)

Run these in a real Claude Code session to close the last gap:

```text
1. /plugin marketplace add <git-url-or-local-path-to-this-repo>
2. /plugin install sift-harness@sift-harness-marketplace
3. Confirm the commands registered:   /sift-plan   (should be offered/known)
4. Confirm hooks fire:
   - open a repo, run `sift plan <some-packet>` to set focus, then attempt an
     edit OUTSIDE that packet's scope.paths → the PreToolUse guard should BLOCK it.
   - start a new session → the SessionStart adapter should surface the resume point.
5. Record the outcome (and any error) back in this file under "Operator run log".
```

### Operator run log (attestation)

Live `/plugin install` is an **operator-attested** step, not CI-verified (there is no
Claude Code test harness in this build context). A maintainer who runs the checklist
above fills one attestation record below. Until a record shows `result: pass`, the live
register-and-fire is **not observed**, schema-valid + relocatable is as far as the
automated bar reaches.

Attestation schema (one record per run):

```yaml
- date:      # ISO date the checklist was run, e.g. 2026-06-03
  host:      # host + version, e.g. "Claude Code v2.1"
  steps:     # which checklist steps were executed (e.g. "1-5")
  result:    # pass | fail | partial, overall register-and-fire outcome
  operator:  # who ran it (name/handle)
  notes:     # commands/hooks observed to register & fire, or any error
```

Records:

```yaml
# (none yet, status: not_observed. Add a record above after a live run.)
```

## Live hook firing (PRV-2), operator-attested

The runtime hooks emit Claude Code block decisions. Engine-level evidence (captured directly
from the installed hook scripts; reproducible via the commands below):

Stop hook, planned-but-not-confirmed packet:

```
{"decision": "block", "reason": "sift packet demo is 'packeted', not confirmed. Run `sift execute demo` then `sift review demo` to reach a witness-bound confirmed before ending the turn."}
```

Engage-gate (FORT-1), a freehand edit then an attempt to stop:

```
{"decision": "block", "reason": "you edited code this session without a sift packet. Run `sift packet new <id>` and drive it to a witness-bound confirmed, or `sift focus --clear` if this was throwaway, before ending the turn."}
```

Reproduce (engine level):
```
w=$(mktemp -d); SIFT_REPO_ROOT=$w bash bin/sift setup
SIFT_REPO_ROOT=$w bash bin/sift packet new demo --profile toy; SIFT_REPO_ROOT=$w bash bin/sift plan demo
printf '{}' | SIFT_REPO_ROOT=$w bash hooks/stop-block.sh
```

**Boundary:** the above proves the hook scripts EMIT the block decision. That a live
Claude Code session HONORS it (refuses to end the turn) is **operator-attested**, an
interactive session cannot be driven headlessly from CI. Operator checklist: in a sift-set-up
repo under Claude Code, (1) ask for a code change without planning a packet, attempt to end the
turn, observe the turn is blocked with the engage-gate reason; (2) `/sift-harness:sift-plan` a
packet, attempt to stop before review, observe the Stop block; (3) drive to `confirmed`, observe
the turn ends. `not_observed != absent`: the mechanism is verified at the engine; the host
honoring is attested, not auto-claimed.

## Host-contract loop (PRV-3). CI-verified

`tests/p19-host-contract.sh` (in `sift selftest`) plays a Stop-honoring host against a scripted
agent: it loops on `stop-block.sh`, refuses to end while the hook returns `decision:block`, lets
the agent take one remediation step per refusal, and ends only when the hook allows, asserting
the turn cannot end until `sift state` is `confirmed`. This auto-verifies the refuse→remediate→
release LOOP a real host runs (stronger than PRV-2's "the hook emits a block").

**Boundary (unchanged):** PRV-3 verifies the host CONTRACT deterministically; it does not
prove a live LLM *chooses* to comply once blocked, that single step stays operator-attested
(`not_observed != absent`).
