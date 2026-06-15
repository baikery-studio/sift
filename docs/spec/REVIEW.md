# W3 review: keyless default, host-verdict mode, and the landing verb

W3 is the review witness in the deterministic quartet (W1 hash-pin, W2 reproduce, scope guard,
W4 wiring). A `confirmed` is witness-bound only if W3 produced a `pass` verdict artifact at
`.harness/reviews/<id>.w3.json`, whose hash the confirmed event records. Two W3 modes exist,
both **zero egress** (no network, no model API, no keys, no data leaves the machine).

## Anti-tamper re-scan at review time

The harness scans for test-tampering signatures (a skipped or early-returned test, a
commented-out assertion, a CI `continue-on-error`) with `kernel/_signatures.py`. That scan runs
at `sift execute` over the packet test plus its acceptance snapshot, and AGAIN at `sift review`
over the packet's whole committed changed set (the pinned manifest `base_sha..HEAD`, falling
back to `HEAD~1..HEAD`, then the working diff). The review-time pass exists because the gate
that mints the witness-bound terminal must see every changed file: a weakened sibling test
introduced after execute would otherwise reach a clean `confirmed`. A signature hit transitions
`reviewing -> review_failed` with the same fail-closed semantics as the execute-time gate, so
`sift state` is not `confirmed`. The scanner recognises shell (`.sh`) test files alongside the
other languages, so this harness's own `.sh` acceptance tests are covered.

## Keyless default

`profiles/software/witness_w3.sh` runs a deterministic structural check: it renders the rubric
plus the diff into a review request and passes only a well-formed request carrying a diff. A
`confirmed` under keyless W3 means "structurally reviewed". The deterministic quartet carries
the real weight, and under an agent host the driving agent already read the diff, so a separate
cloud reviewer would be redundant. Fail-closed: a malformed request rejects.

## Host-verdict mode (the agent in the loop is the reviewer)

Opt in with `SIFT_W3_REQUIRE_HOST_VERDICT=1` or `witnesses.w3.require_host_verdict: true` in
`profile.json`. W3 then stops minting its own pass and instead VALIDATES an agent-authored
R1-R13 rubric verdict. The verdict must be a single JSON object with `verdict: "pass"`,
`confidence` present (>= 0.5), and a complete `R1..R13` rubric dict. The parser is
injection-resistant: it scans every top-level object carrying a `verdict` key, and a planted
second verdict (smuggled through the diff) fails closed to `reject`. Still zero egress: the
verdict comes from the agent already in the loop, not a remote model.

## The landing verb: `sift w3-verdict <id> <staging-file> [--force]`

Host-verdict mode needs the agent's verdict to reach `.harness/reviews/<id>.w3.json`. But
`kernel/scope_guard.sh` HARD-DENIES every agent write under `.harness/` (the forge channel),
focus or not. A reviewer that holds the pen on its own provenance record is not a control, so
the deny stays. The resolution is a sanctioned door, not a hole in the fence:

1. The agent writes its verdict JSON to an **in-scope** staging path it is allowed to write
   (under the packet's `scope.paths`, or a designated staging file).
2. `sift w3-verdict <id> <staging>` validates the SHAPE with sift's OWN code, the same
   single-source `witness_w3.sh --validate-file` validator review-time W3 applies (parseable
   JSON, single verdict object, `pass`, confidence, complete rubric). A malformed or
   double-verdict staging file is REFUSED and **no artifact is written**.
3. On a valid verdict, sift's python lands the canonical artifact atomically (tmp + rename).
   The agent never touches `.harness/` directly.

The verb refuses to clobber an existing verdict for that id unless `--force`. It does NOT decide
pass/fail semantics (that is W3 at review time plus the rubric-value check). It only lands a
well-formed verdict past the fence. The boundary is preserved: the scope guard still denies
direct `.harness/` writes, and the only way in is sift's code doing the write.
