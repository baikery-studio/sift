#!/usr/bin/env python3
"""sift-harness kernel — state by CAUSALLY-VALIDATED replay over the hash-chained log.

project_state(packet_id):
  1. verify the chain (tamper-evidence)  → corrupt on any break
  2. replay this packet's lane.transitions IN SEQ ORDER
  3. validate every (from,to) against the transition table  → corrupt on illegal edge
  4. for any ...→confirmed, REQUIRE valid witness-evidence bound to real artifacts
     → corrupt on a forged/witnessless confirmed

A `confirmed` event is authentic only if it references — by `event_hash` — a
PRIOR, hash-chained `review.verdict` event for the SAME packet whose recorded
verdict is "pass". Because that reference rides on the tamper-evident chain, a
worker can no longer mint a `confirmed` by writing a side-file and quoting its
hash (the self-minted-artifact forge): there must be a real, chained verdict
event, and the w3_hash must match both that event and the on-disk artifact.

Honesty bound (no secret key — single-operator tool): this is tamper-EVIDENT,
not tamper-PROOF. A determined operator who hand-writes the FULL event sequence
(a fake review.verdict + a confirmed referencing it) can still forge, and the
chain will verify — it is THEIR own log. What this defeats is the lazy / partial
/ accidental premature-done: a witnessless confirmed, a self-minted side-file
with no verdict event, or a confirmed quoting a verdict event that says "reject".
"""
import sys, os, json, hashlib, unicodedata

GENESIS = "0" * 64

# the 11-state machine (PROFILE_INTERFACE §1.1) — the only legal edges
TRANSITIONS = {
    ("submitted", "packeted"),
    ("packeted", "executing"),
    ("executing", "acceptance_met"), ("executing", "failed"), ("executing", "blocked"),
    ("acceptance_met", "reviewing"),
    ("reviewing", "confirmed"), ("reviewing", "partially_confirmed"), ("reviewing", "review_failed"),
    ("partially_confirmed", "reviewing"),
    ("review_failed", "executing"),
    ("failed", "executing"),
    ("blocked", "packeted"),
}
REQUIRED_WE = ["verdict_event", "feature_sha", "extended_hash", "w1_ok", "w2_hash", "w3_hash", "w4_hash"]


def _canon(obj):
    # MUST stay byte-identical to _log.py _canon (NFC + ensure_ascii=False), or
    # verify re-derives a different hash than append wrote.
    return unicodedata.normalize("NFC", json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False))


def _verify_chain(lines):
    prev_hash, prev_seq = GENESIS, 0
    for i, ln in enumerate(lines, 1):
        try:
            ev = json.loads(ln)
        except Exception:
            return (False, i)
        content = {k: v for k, v in ev.items() if k != "event_hash"}
        h = hashlib.sha256(_canon(content).encode("utf-8")).hexdigest()
        if h != ev.get("event_hash") or ev.get("prev_hash") != prev_hash or ev.get("seq") != prev_seq + 1:
            return (False, i)
        prev_hash, prev_seq = ev["event_hash"], ev["seq"]
    return (True, len(lines))


def _valid_witness(we, packet_id, reviews_dir, by_hash, confirmed_seq):
    """Authenticate a `confirmed`'s witness-evidence against a chained verdict event.

    by_hash: {event_hash -> event} for THIS packet's events (all kinds).
    confirmed_seq: seq of the confirmed event; the verdict event must PRECEDE it.
    """
    if not isinstance(we, dict):
        return False
    # field presence — explicit per-field (no 0==False / and-or precedence trap).
    for k in REQUIRED_WE:
        if k not in we:
            return False
        v = we[k]
        if k == "w1_ok":
            if v is not True:
                return False
        elif v is None or v == "":
            return False
    # the referenced verdict event must exist IN-CHAIN, be a review.verdict for
    # this packet, and record verdict == "pass".
    ve = by_hash.get(we["verdict_event"])
    if not ve or ve.get("kind") != "review.verdict" or ve.get("packet_id") != packet_id:
        return False
    if not isinstance(ve.get("seq"), int) or ve["seq"] >= confirmed_seq:  # must PRECEDE
        return False
    vw = ve.get("witness_evidence")
    if not isinstance(vw, dict) or vw.get("verdict") != "pass":
        return False
    if vw.get("feature_sha") != we.get("feature_sha"):
        return False
    # w3_hash must match the verdict event AND the on-disk fresh W3 artifact.
    art = os.path.join(reviews_dir, packet_id + ".w3.json")
    if not os.path.exists(art):
        return False
    with open(art, "rb") as f:
        actual = hashlib.sha256(f.read()).hexdigest()
    return actual == we.get("w3_hash") and vw.get("w3_hash") == we.get("w3_hash")


def project_state(log_path, packet_id, reviews_dir):
    if not os.path.exists(log_path):
        return "submitted"
    lines = [ln.rstrip("\n") for ln in open(log_path) if ln.strip()]
    # Always verify the full hash-chain (HD2-1: the whole-file-SHA checkpoint was dropped —
    # measured ~1.4x, not load-bearing, and a keyless file checkpoint is forgeable by any
    # operator who can write .harness/, so a lazy tamper + matching file_sha could skip
    # verification. No accelerator means no file an operator can write lets a tampered log
    # pass as clean; the only way through is a fully-valid rewritten chain (the documented
    # ceiling).
    ok, _ = _verify_chain(lines)
    if not ok:
        return "corrupt"
    transitions, by_hash = [], {}
    for ln in lines:
        ev = json.loads(ln)
        if ev.get("packet_id") != packet_id:
            continue
        by_hash[ev.get("event_hash")] = ev
        if ev.get("kind") == "lane.transition":
            transitions.append(ev)
    transitions.sort(key=lambda e: e["seq"])
    state = None
    used_verdicts = set()                     # a verdict_event backs ONE decision (no double-spend)
    for ev in transitions:
        frm, to = ev.get("from") or "submitted", ev.get("to")
        if state is None:
            if frm != "submitted":
                return "corrupt"
            state = "submitted"
        if frm != state:                      # continuity enforced BEFORE any accept
            return "corrupt"
        if to == "superseded":                # retirement: legal from any reached state
            state = "superseded"; continue
        if (frm, to) not in TRANSITIONS:
            return "corrupt"
        # BOTH terminal-grade states must be witness-bound: a soft-floored
        # `partially_confirmed` still means a real W3 verdict ran (the cap comes from
        # W2/W4), so it must reference a valid in-chain verdict event the same way
        # `confirmed` does. Without this, a hand-forged partially_confirmed (no/bogus
        # witness) replays clean — the same premature-done forge `confirmed` rejects.
        if to in ("confirmed", "partially_confirmed") \
           and not _valid_witness(ev.get("witness_evidence"), packet_id, reviews_dir, by_hash, ev["seq"]):
            return "corrupt"
        # a verdict_event referenced by confirmed/partially_confirmed is consumed
        # once — reusing it (e.g. to skip a required re-review) is corrupt.
        if to in ("confirmed", "partially_confirmed"):
            we = ev.get("witness_evidence")
            if isinstance(we, dict) and we.get("verdict_event"):
                if we["verdict_event"] in used_verdicts:
                    return "corrupt"
                used_verdicts.add(we["verdict_event"])
        state = to
    return state or "submitted"


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.stderr.write("usage: _state.py <log_path> <packet_id> <reviews_dir>\n"); sys.exit(2)
    print(project_state(sys.argv[1], sys.argv[2], sys.argv[3]))
