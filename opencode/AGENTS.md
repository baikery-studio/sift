# sift-harness — opencode adapter

sift-harness enforces **plan → execute → review** rigor: every unit of work is a
hash-pinned *packet* driven to a witness-bound `confirmed` through an append-only,
tamper-evident log — so an agent can't declare work premature, unwired, or forged.

The engine is host-agnostic. From this repo, drive it with `bin/sift`:

```
SIFT_REPO_ROOT="$(pwd)" bash <SIFT_HOME>/bin/sift <verb> [args]
```
where `<SIFT_HOME>` is where this plugin is installed/cloned.

Verbs: doctor execute init-claudemd new next plan review + state status verify-log selftest setup wave-review focus packet.

The loop: `packet new` → produce the artifact → `plan` → `execute` → `review` → `confirmed`.

> Capability on opencode: see docs/spec/HOSTS.md. The witness-bound trust core works here
> via `bin/sift`. Runtime scope-guard *enforcement* requires a PreToolUse-style hook;
> where the host lacks one, the scope guard is advisory (guidance), not enforced.
