---
name: sift-workflow
description: "Use when a coding task warrants rigor, a multi-step change, a fix that must be verified, or anything where you must not declare \"done\" prematurely. Drives the work as a sift packet through plan → execute → review to a witness-bound confirmed, so completion is checked, scoped, and logged rather than asserted."
version: 0.3.0
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [sift, harness, plan-execute-review, witness, packet, verify]
---

# sift-workflow

**This skill is the entry point, start here.** It drives the whole loop for you; the
`/sift-harness:sift-*` slash commands are manual controls for stepping a single phase by
hand when you want to. For normal work, follow this skill end to end.

When a task deserves more than a quick edit, it's multi-step, it must be verified,
or "done" needs to mean *checked*, drive it through the harness instead of
declaring completion yourself. The harness turns the work into a **packet** and only
lets it reach `confirmed` when independent witnesses pass.

Run these from the repo root (the plugin's `bin/sift`; in Claude Code the same verbs
are the `/sift-*` commands).

## The loop

1. **Scaffold a packet.** `sift packet new <id> --profile toy` (or `software`) writes
   a packet + an acceptance-test stub. Then `sift packet validate <id>` checks it.
   Fill in the goal, the `scope.paths` (the files this work may touch), and the
   acceptance test (what proves it done).

2. **Plan.** `sift plan <id>` moves it `submitted → packeted` and sets it as the
   active *focus*. From here the PreToolUse scope guard fences your edits to the
   packet's `scope.paths`, if you try to edit outside, it blocks you.

3. **Do the work, in scope.** Make the change and produce the declared artifact /
   make the acceptance test pass. Stay within `scope.paths`.

4. **Execute.** `sift execute <id>` runs the acceptance check (`→ acceptance_met`).
   If it fails, fix and re-run; don't proceed on red.

5. **Review.** `sift review <id>` runs the witnesses (W2 reproduce, W3 review, W4
   wiring) and, only if they pass, writes a witness-bound `confirmed` event and
   clears the focus. Check `sift state <id>` → `confirmed`.

If you're resuming after a break, `sift next <wave>` tells you the next actionable
packet (state is replayed from the log, so it survives a context compaction).
`sift doctor` flags a confirmed packet whose review artifact went missing.

## What's real (and what isn't)

- **The witnesses, the witness-binding, the log, and the scope guard are the
  enforcement.** A `confirmed` that no witness backed replays as `corrupt`.
- **The scope guard is advisory**, it protects only when the host runs the
  PreToolUse hook; it is not a kernel sandbox.
- **Review is keyless and local.** W3 runs a deterministic structural check: no model
  API, no network, no keys, nothing leaves your machine. Under Claude Code the agent
  driving the loop is itself the model doing the real review.

## Limits

This skill points you at the loop; the machinery enforces it, and where it enforces
depends on the host:

- **Under Claude Code:** the **Stop hook** makes the turn un-endable while a packet is
  planned-but-not-confirmed, and the **scope guard** fences edits to the packet's
  `scope.paths`. That is runtime enforcement (host-honored, not a kernel sandbox).
- **Everywhere (all hosts):** the hash-chained **trust-core** is the hard backstop, a
  `confirmed` no witness backed, or a hand-edited log, replays as `corrupt`. Completion
  is witness-bound, not asserted.

On a host without hooks the live steering degrades to guidance, but the trust-core
backstop never does.
