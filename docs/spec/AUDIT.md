# sift audit — second-party replay-verification

`sift audit <packet_id>` lets a party who did **not** build the work verify a
`confirmed` claim from the repo plus the retained trust artifacts (the hash-chained log
and the witness reviews). It is the capability the architecture is closest to serving
(regulated / multi-party hand-off) and the one a self-asserted "done" cannot offer.

Note that `.harness/log.jsonl` and `.harness/reviews/` are gitignored by default, so a
plain `git clone` does **not** carry them. Audit is not "from a bare clone" — the
operator must ship or retain those artifacts (see *What a second party needs*).

## What it checks

Given only the repo + `.harness/log.jsonl` + `.harness/reviews/`, audit runs three
independent checks and prints a structured verdict:

1. **Chain** — `verify-log` re-derives every `event_hash` and the `prev_hash`/`seq`
   linkage. Any edit, insert, reorder, or delete fails here (exit ≠ 0). A
   schema-too-old log is reported distinctly (run `sift migrate-log`).
2. **Replay** — `project_state` replays the packet's transitions and returns
   `confirmed` only if the terminal event is bound to a prior, in-chain
   `review.verdict` whose verdict is `pass`, with matching `feature_sha` and witness
   hashes. A witnessless or forged `confirmed` replays as `corrupt` and fails here.
3. **Artifacts** — each bound `w2_hash` / `w3_hash` / `w4_hash` is recomputed from the
   on-disk `.w2.json` / `.w3.json` / `.w4.json` and compared to the value in the
   confirmed event. A missing artifact (MISSING) or a content-swapped one (TAMPERED)
   fails here.

PASS prints the bound evidence (feature_sha, verdict_event, the three artifact
hashes). FAIL prints the exact reason. Exit code mirrors the verdict.

## Honesty bound

Audit is **tamper-evident, not tamper-proof**. There is no secret signing key (this
is a single-operator tool), so an operator who rewrites the entire hash chain
consistently can still forge a clean-verifying log of their own. What audit defeats is
the lazy / partial / premature `confirmed`: a witnessless terminal event, a self-minted
artifact with no chained verdict, a confirmed quoting a `reject` verdict, or a
content-tampered artifact. Treat a PASS as "this confirmed is internally consistent and
witness-bound in this log," not as a cryptographic attestation against a hostile author.

## Provenance

The witness evidence records `feature_sha` (the commit the work was reviewed against)
and the W3 artifact hash, so a PASS resolves to a specific commit. When the published
repository squashes history, ship a committed provenance manifest mapping each confirmed
packet → commit SHA + w3 hash so `feature_sha` stays resolvable from the shipped repo.

## What a second party needs

`sift audit` is not satisfied by a bare `git clone`. To replay-verify a `confirmed`, the
auditor needs three inputs together:

1. **The repo** at (or resolving to) the recorded `feature_sha` — the source the work was
   reviewed against.
2. **`.harness/log.jsonl`** — the hash-chained event log. Gitignored by default, so the
   operator must ship it out of band, commit it deliberately, or hand it over with the repo.
3. **`.harness/reviews/<id>.w2.json` / `.w3.json` / `.w4.json`** — the witness artifacts
   whose hashes the confirmed event binds. Also gitignored by default; ship them alongside
   the log.

For a published or squashed repo, a committed provenance manifest (per *Provenance*) plus
the shipped log and reviews is the practical hand-off package. Without the log and reviews
there is nothing to verify — audit reports FAIL (no confirmed event / missing artifact),
never a false PASS.
