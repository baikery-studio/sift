# Security Policy

sift is a single-operator, local harness for AI coding CLIs. It raises the cost of an agent
faking "done." It is a process tool, not a sandbox or a cryptographic vault. This document
states what it does and does not protect against, so you can place it in your own threat model.

## Reporting a vulnerability

Report security issues privately. Do not open a public issue for an unfixed vulnerability.

- Preferred: open a private report via GitHub Security Advisories ("Report a vulnerability") on
  this repository.

Include repro steps, affected version, and impact. You get an acknowledgement; a fix or
mitigation timeline follows triage.

## Supported versions

This project is pre-1.0 (`0.3.x`). Only the latest line receives security fixes; older snapshots
stay unpatched. Pin a commit if you need stability and watch releases for advisories.

## Threat model

### The log is tamper-evident: detection, not prevention

Completion state lives in a hash-chained, append-only event log. Editing or deleting a past
event breaks the chain, so tampering is detectable (`sift verify-log`). There is no secret
signing key, so an attacker who can run code as you can rewrite the whole chain consistently and
the hashes alone will not reveal it. Treat the log as a high-integrity audit trail against an
*agent* cutting corners, not as a defense against a hostile *operator* on your own machine.

### The scope guard is advisory

The PreToolUse scope guard fences edits to the active packet's `scope.paths`. A host hook you
install (`hooks/hooks.json`) enforces it, and it governs only tool calls that route through that
hook. It fails closed: a parse error or a missing focus packet denies the edit. It stays
advisory. A process that writes files outside the host's tool layer (a raw shell `cat >`, a
second editor, a misconfigured host) is not intercepted. It reduces accidental scope drift. It
does not contain a determined or out-of-band writer.

### The Bash tool is not fully contained

The scope guard and the deny layer govern edit tools (Edit/Write/MultiEdit) and a named set of
destructive Bash commands. They do not sandbox Bash in general. An agent with unrestricted Bash
can still (a) write `.harness/` provenance directly via a shell redirect or
`python3 kernel/_log.py`, hand-forging a full event sequence the chain will validate (this is the
detection-not-prevention ceiling above: no secret key, single operator), and (b) send data over
the network with `curl`/`wget`/a Python socket. sift itself makes no network calls, but it does
not sandbox the agent's Bash, so it cannot stop an agent from doing so. Closing these needs an
OS/container sandbox or a host network allowlist, out of scope for this tool, which runs
unsandboxed by design (see *Host execution model*). Prefer a container for untrusted packets, and
do not grant unconstrained Bash to an agent you would not trust with your machine.

### The deny layer is advisory host permissions

`.claude-plugin/settings.json` declares a `permissions` deny/ask set (no `sudo`, no `rm -rf`, no
force-push / `--no-verify` / `reset --hard`, no read or write of `.env`/`*.pem`/`*.key`/`.ssh`)
plus a `deniedDomains` list (cloud-metadata endpoints + known paste sites) and a subprocess
env-scrub. This raises the cost of the most common destructive and exfil actions. It stays
advisory: the host that reads `settings.json` enforces it on routed tool calls, and the
network/filesystem rules apply only when the host's sandbox is active. sift does not provide the
sandbox, and the deny layer does not stop an out-of-band writer. Treat it as sensible defaults,
not a boundary.

## Data egress

sift makes no network calls. There is no network egress. The review witness (W3) runs keyless
and deterministic on your machine: no model API, no API key, and no opt-in send. Your code never
leaves your machine through sift. The one caveat is the Bash point above: sift does not sandbox
the agent, so an agent with Bash could `curl` data out on its own; that is a host-sandbox
concern, not something sift transmits.

## Host execution model

The engine runs shell and Python on your host to drive acceptance tests, witnesses, and
scaffolding. It is not sandboxed and runs with your user's full privileges and host filesystem
access.

Run it with Docker to isolate the harness in a container. Without Docker there is no container
boundary: packet acceptance scripts and witnesses execute unsandboxed as your user. Treat a
packet's acceptance/witness scripts as code you are choosing to run. Run only packets you trust,
and prefer a container (or a throwaway VM / `env -i` minimal environment) for untrusted ones.

## Summary

| Property | Reality |
|----------|---------|
| Completion log | tamper-evident (detectable), no secret key |
| Scope guard | advisory, host-hook enforced, fails closed |
| Deny layer | advisory host permissions (deny destructive Bash + secret read/write + metadata/paste egress), not a sandbox |
| Network egress | none — sift makes no network calls; W3 review is keyless and local |
| Execution | host shell/Python, unsandboxed without Docker |

The point is disclosure over assertion. Use it for process rigor, not as a security boundary.
