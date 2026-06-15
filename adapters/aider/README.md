# Aider adapter

A minimal adapter so [Aider](https://aider.chat) sessions drive sift-harness. Aider has
no hook lifecycle, so this is the **trust-core-only** path: no live scope guard, no
un-endable turn — but a `confirmed` is still witness-bound and a forged log still replays
as `corrupt`. That is the guarantee that travels to every host.

## Wire it

1. Copy `AGENTS.md` from this directory into your repo root (Aider reads `AGENTS.md`
   automatically), or add `/path/to/sift-harness/adapters/aider/AGENTS.md` to Aider's
   read list:

   ```
   aider --read adapters/aider/AGENTS.md
   ```

2. Drive the loop with the bare CLI (`bin/sift`) exactly as `AGENTS.md` describes —
   `setup → packet new → plan → execute → commit → review → confirmed`.

## What travels vs what doesn't

- **Travels (trust core):** hash-chained log, causal replay, witness-bound `confirmed`,
  `sift audit`. Identical to every other host.
- **Claude-Code-only (runtime hooks):** the PreToolUse scope guard and the Stop gate.
  Under Aider those degrade to the guidance in `AGENTS.md`; the trust core does not.

See [`docs/spec/HOSTS.md`](../../docs/spec/HOSTS.md) for the full host matrix and the
observed-vs-attested boundary.
