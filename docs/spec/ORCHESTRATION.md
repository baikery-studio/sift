# Orchestration: decisions above the core

`sift audit` answers WHAT was built (the witness-bound confirmeds). `sift trace` answers WHY each
step was chosen (the orchestrator's decisions). Both ride the same tamper-evident hash chain, but
the orchestrator's record can never move a packet's state.

## The above-core boundary (emergent, load-bearing)

The trust core is deliberately narrow: `kernel/_state.py` replay consumes ONLY
`kind == "lane.transition"` and binds a terminal ONLY via `kind == "review.verdict"`. Every other
event kind is hash-chained and tamper-checked by `kernel/_log.py` (which takes `kind` straight
from the caller with no allowlist) yet is INERT to state projection. An orchestrator event is one
of those inert kinds, so it is verifiable and ordered on the chain without ever being able to
confirm, corrupt, or otherwise move a packet.

This inertness is EMERGENT, not a special case: the core does not know about orchestrator events,
it simply ignores any kind it does not consume. Do NOT add `orch.*` to a kind-allowlist or a new
edge in the transition table: that would couple the orchestrator to the trust root and break the
boundary. The regression test in ORCH-4 locks this: injecting arbitrary `orch.*` events leaves a
confirmed packet confirmed and the chain verifying.

## The orchestrator event vocabulary

Emitted via the sanctioned helper `sift_orch_log <wave-id> <kind> <json-reason>` (actor
`orchestrator`, on the reserved wave scope `__wave__:<wave-id>` since a wave-level event has no
member packet). The driver never hand-rolls `log_append`.

- `orch.decision`: a dispatch or halt choice, e.g. `{"action":"dispatch","reason":"next=<id>"}`
  or `{"action":"halt","reason":"retry_ceiling"}` (the economic-governor halt rides this kind so
  it surfaces in the trace).
- `packet.emit`: a scaffolded covering packet, e.g. `{"packet":"<id>","reason":"coverage gap"}`.
- `coverage.gap`: an uncovered requirement.

## Reading the trace

`sift trace <wave-id>` reads the VERIFIED log and prints, in chain order, the orchestrator
decisions scoped to that wave (`__wave__:<wave-id>`). It filters by wave, so one wave's trace
never leaks another's. It is read-only and makes no network calls (zero egress). If the chain
does not verify it warns that the trace is from a tampered log.
