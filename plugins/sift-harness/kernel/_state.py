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
import sys, os, json, hashlib, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _canon import canon as _canon   # SINGLE source of canonicalization (shared with _log.py)

GENESIS = "0" * 64

# the 11-state machine (PROFILE_INTERFACE §1.1) — the only legal edges
TRANSITIONS = {
    ("submitted", "packeted"),
    ("packeted", "executing"),
    ("executing", "acceptance_met"), ("executing", "failed"),
    ("acceptance_met", "reviewing"),
    ("reviewing", "confirmed"), ("reviewing", "partially_confirmed"), ("reviewing", "review_failed"),
    ("partially_confirmed", "reviewing"),
    ("review_failed", "executing"),
    ("failed", "executing"),
}
# `blocked` removed (AR-2): no code path ever emitted it, and `sift abort` provides in-band
# recovery (reviewing->review_failed, executing->failed). `superseded` is handled at replay
# (retirement from any reached state) and emitted by `sift supersede`. `partially_confirmed`
# is emitted by the soft-floor cap (AR-3).
REQUIRED_WE = ["verdict_event", "feature_sha", "extended_hash", "w1_ok", "w2_hash", "w3_hash", "w4_hash"]


def _verify_chain(lines):
    """Back-compat shim: verify a list of RAW lines. Parses then delegates to the parsed check.
    Returns (ok, idx): idx is the failing line on a parse error, else the line count (callers
    that need the precise break offset use verify-log; _audit.py discards idx)."""
    events = []
    for i, ln in enumerate(lines, 1):
        try:
            events.append(json.loads(ln))
        except Exception:
            return (False, i)
    return (_verify_chain_parsed(events), len(lines))


def _verify_chain_parsed(events):
    """The hash-chain check over ALREADY-PARSED events (single-pass: callers parse each line
    once and reuse the list for both verify and replay). Returns True iff the whole chain
    re-derives clean."""
    prev_hash, prev_seq = GENESIS, 0
    for ev in events:
        content = {k: v for k, v in ev.items() if k != "event_hash"}
        h = hashlib.sha256(_canon(content).encode("utf-8")).hexdigest()
        if h != ev.get("event_hash") or ev.get("prev_hash") != prev_hash or ev.get("seq") != prev_seq + 1:
            return False
        prev_hash, prev_seq = ev["event_hash"], ev["seq"]
    return True


# SCALE-MEMO: per-INVOCATION verified-event cache. project_state runs PER PACKET in loops
# (doctor/status/wave/drive); re-verifying the whole chain on every call is O(P×N). This caches
# the parsed+verified event list keyed by (realpath, mtime_ns, size) so a single process verifies
# ONCE and reuses the list across every projection -> O(N+P). It lives in-PROCESS only: a fresh
# `sift` invocation starts empty, so there is NO persisted, operator-writable checkpoint a tampered
# log could ride (the deliberate reason HD2-1's file checkpoint was dropped). Any mtime/size change
# re-verifies. The cache holds only the VERIFIED-CLEAN list; per-packet witness re-hashing still
# runs every projection, so a content-tampered artifact is still caught — byte-identical semantics.
_VCACHE = {}


def _trace_verify():
    tf = os.environ.get("SIFT_VERIFY_TRACE")
    if tf:
        try:
            with open(tf, "a") as f:
                f.write("verify\n")
        except Exception:
            pass


def _load_verified(log_path):
    """Return (ok, events) for the log, parsing each line ONCE and verifying the chain ONCE per
    process invocation (memoized). A FULL verify (cache miss) emits a SIFT_VERIFY_TRACE line."""
    # Cache key from a single O(1) stat (NOT a content hash — hashing to form the key would
    # re-read the log on every call and reintroduce O(P×N), defeating the memo). Include ino +
    # ctime_ns + mtime_ns + size: an append bumps size/mtime; an in-place rewrite bumps ctime
    # (which os.utime CANNOT forge, unlike mtime); a file recreate changes ino. So a
    # length-preserving in-place tamper with a restored mtime still invalidates the cache and
    # re-verifies. The residual (restore the system clock AND recreate with the exact inode,
    # in-process) is far inside the documented single-operator full-chain-rewrite ceiling.
    try:
        stt = os.stat(log_path)
        key = (os.path.realpath(log_path), stt.st_ino, stt.st_ctime_ns, stt.st_mtime_ns, stt.st_size)
    except OSError:
        key = None
    if key is not None and key in _VCACHE:
        return _VCACHE[key]
    events, ok = [], True
    for ln in open(log_path):
        if not ln.strip():
            continue
        try:
            events.append(json.loads(ln))
        except Exception:
            ok = False
            break
    if ok:
        ok = _verify_chain_parsed(events)
    _trace_verify()                      # a full verify happened (cache miss)
    result = (ok, events)
    if key is not None:
        _VCACHE[key] = result
    return result


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
    # Every witness hash binds to BOTH the on-disk artifact AND the verdict event —
    # no field is presence-only. W2 reproduce, W3 review, W4 wiring each wrote a real
    # artifact whose sha256 must equal the hash carried in the confirmed event and the
    # chained verdict event. A decorative literal (w2_hash="reproduced") no longer passes.
    # WITNESS-PLATFORM: bind EVERY witness-hash key data-drivenly, not a literal w2/w3/w4 list,
    # so a profile that declares an extra witness (w5...) has it bound too. A witness-hash key is
    # `w<id>_hash`; its artifact is reviews/<packet>.<id>.json (suffix derived from the key, the
    # same convention pipeline.sh writes). The mandatory defaults w2/w3/w4 are still enforced by
    # REQUIRED_WE presence above, so the software default set is byte-identical and an existing
    # confirmed (carrying exactly w2/w3/w4) binds exactly as before. Each hash must match BOTH
    # the on-disk artifact AND the chained verdict event — no field is presence-only.
    wkeys = sorted(k for k in we if re.match(r"^w\w+_hash$", k))
    for wk in wkeys:
        suffix = "." + wk[:-len("_hash")] + ".json"   # w2_hash -> .w2.json ; w5_hash -> .w5.json
        art = os.path.join(reviews_dir, packet_id + suffix)
        if not os.path.exists(art):
            return False
        with open(art, "rb") as f:
            actual = hashlib.sha256(f.read()).hexdigest()
        if actual != we.get(wk) or vw.get(wk) != we.get(wk):
            return False
    # extended_hash binds the confirmed to the exact packet it reviewed. Prefer the PINNED
    # snapshot (<id>.packet, written at review time, immutable, travels with reviews). Fall
    # back to the live packet file for pre-pinning confirmeds. FAIL CLOSED when NEITHER
    # exists — that absent-source path was the fail-open a garbage extended_hash exploited.
    snap = os.path.join(reviews_dir, packet_id + ".packet")
    pkt = snap if os.path.exists(snap) else _packet_path(packet_id, reviews_dir)
    if not pkt or not os.path.exists(pkt):
        return False
    with open(pkt, "rb") as f:
        if hashlib.sha256(f.read()).hexdigest() != we.get("extended_hash"):
            return False
    return True


def _packet_path(packet_id, reviews_dir):
    """Live packet path for pre-pinning (legacy) confirmeds. Prefers SIFT_PACKETS, else the
    standard <repo>/tasks/packets layout derived from the reviews dir."""
    pdir = os.environ.get("SIFT_PACKETS")
    if not pdir:
        repo = os.path.dirname(os.path.dirname(os.path.abspath(reviews_dir)))
        pdir = os.path.join(repo, "tasks", "packets")
    return os.path.join(pdir, packet_id + ".md")


def project_state(log_path, packet_id, reviews_dir):
    if not os.path.exists(log_path):
        # no log at all: a real (but unplanned) packet has a packet file -> submitted; a
        # nonexistent id (typo) has neither file nor events -> unknown, not a misleading submitted.
        return "submitted" if os.path.exists(_packet_path(packet_id, reviews_dir)) else "unknown"
    # Verify the full hash-chain — ONCE per process invocation, then reuse the verified event
    # list for this and every other per-packet projection (SCALE-MEMO). There is still NO
    # persisted accelerator: the memo is in-process only, rebuilt every fresh invocation, so no
    # file an operator can write lets a tampered log pass as clean; the only way through is a
    # fully-valid rewritten chain (the documented ceiling). The per-packet witness re-hash below
    # still runs every projection, so a content-tampered artifact is still caught.
    ok, events = _load_verified(log_path)
    if not ok:
        return "corrupt"
    transitions, by_hash = [], {}
    for ev in events:
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
    if state is None:
        # no transitions for this id. A real submitted packet has a packet file; a nonexistent
        # id with no events and no file is "unknown" (a typo), not a misleading "submitted".
        if not by_hash and not os.path.exists(_packet_path(packet_id, reviews_dir)):
            return "unknown"
        return "submitted"
    return state


if __name__ == "__main__":
    # batch: _state.py --batch <log> <reviews> <id...>  — project MANY packets in ONE process,
    # so the chain is verified ONCE (the memo) and reused. Prints "<id>\t<state>" per id. Used by
    # doctor/status/wave loops to drop the O(P×N) re-verify factor to O(N+P).
    if len(sys.argv) >= 4 and sys.argv[1] == "--batch":
        log, reviews = sys.argv[2], sys.argv[3]
        for pid in sys.argv[4:]:
            print("%s\t%s" % (pid, project_state(log, pid, reviews)))
        sys.exit(0)
    if len(sys.argv) < 4:
        sys.stderr.write("usage: _state.py <log_path> <packet_id> <reviews_dir> | --batch <log> <reviews> <id...>\n"); sys.exit(2)
    print(project_state(sys.argv[1], sys.argv[2], sys.argv[3]))
