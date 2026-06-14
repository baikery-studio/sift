#!/usr/bin/env python3
"""sift-harness — second-party audit report for a witness-bound terminal packet.

  _audit.py <log_path> <packet_id> <reviews_dir>   # exit 0 PASS, 1 FAIL

SELF-SUFFICIENT (TRUST-AUDIT-1): this verifier carries its OWN guarantee. Before the
artifact report it (1) re-derives every event_hash and checks prev_hash/seq over the whole
log — a tampered chain FAILS — and (2) replays the packet via project_state, which enforces
the witness binding (verdict_event references a real review.verdict==pass, no double-spend,
extended_hash matches) — a forged/witnessless terminal replays as `corrupt` and FAILS. Both
checks reuse _state.py's exact logic (single source), so _audit.py can no longer be the weak
link when a new entrypoint (audit --bundle, signature-verify) calls it directly without
audit.sh's gating. audit.sh keeps its own checks too (defence in depth).

A witness-bound terminal is {confirmed, partially_confirmed}: _state.py binds both with the
same witness rigour, so both are auditable; the report names the grade. After the chain +
replay gates, this re-derives the bound artifact hashes for the human-readable verdict report
a second party reads: feature_sha + verdict_event + the W2/W3/W4 artifact hashes, each
re-checked against its on-disk file. Stdlib only.
"""
import sys, os, json, hashlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _state import project_state, _verify_chain   # SINGLE source of chain-verify + witness replay

log_path, pid, reviews = sys.argv[1], sys.argv[2], sys.argv[3]
TERMINALS = ("confirmed", "partially_confirmed")

# (1) chain verification — recompute every event_hash, check prev_hash/seq. A partial tamper
# (a mutated content field with a stale event_hash) FAILS here, before any artifact rehash.
_lines = [ln.rstrip("\n") for ln in open(log_path)] if os.path.exists(log_path) else []
_lines = [ln for ln in _lines if ln.strip()]
_chain_ok, _ = _verify_chain(_lines)
if not _chain_ok:
    sys.stderr.write("AUDIT FAIL (%s): log chain does not verify (tampered or schema-too-old)\n" % pid)
    sys.exit(1)

# (2) witness binding — replay state. A forged verdict_event, a double-spent verdict, or a
# mismatched extended_hash replays as `corrupt`; only a genuine witness-bound terminal passes.
_state = project_state(log_path, pid, reviews)
if _state not in TERMINALS:
    sys.stderr.write("AUDIT FAIL (%s): replays as '%s', not a witness-bound terminal\n" % (pid, _state))
    sys.exit(1)


def _events():
    out = []
    if not os.path.exists(log_path):
        return out
    for ln in open(log_path):
        if ln.strip():
            try:
                out.append(json.loads(ln))
            except Exception:
                pass
    return out


confirmed, grade, by_hash = None, None, {}
for e in _events():
    if e.get("event_hash"):
        by_hash[e["event_hash"]] = e
    if e.get("kind") == "lane.transition" and e.get("to") in TERMINALS and e.get("packet_id") == pid:
        confirmed, grade = e, e.get("to")     # last terminal wins (matches replay's final state)
if confirmed is None:
    sys.stderr.write("AUDIT FAIL (%s): no witness-bound terminal event in the log\n" % pid)
    sys.exit(1)

we = confirmed.get("witness_evidence")
if not isinstance(we, dict):
    sys.stderr.write("AUDIT FAIL (%s): confirmed carries no witness_evidence\n" % pid)
    sys.exit(1)

problems = []
for wk, suf in (("w2_hash", ".w2.json"), ("w3_hash", ".w3.json"), ("w4_hash", ".w4.json")):
    bound = we.get(wk)
    if not bound:
        problems.append("%s: not bound in confirmed event" % wk)
        continue
    art = os.path.join(reviews, pid + suf)
    if not os.path.exists(art):
        problems.append("%s: artifact %s MISSING" % (wk, suf))
    elif hashlib.sha256(open(art, "rb").read()).hexdigest() != bound:
        problems.append("%s: artifact %s TAMPERED (hash != bound)" % (wk, suf))

if problems:
    sys.stderr.write("AUDIT FAIL (%s):\n  %s\n" % (pid, "\n  ".join(problems)))
    sys.exit(1)

# w3_mode is additive/optional evidence (W3-SEM-1): which review regime backed this confirmed
# (host R1-R13 verdict vs keyless structural floor). Absent on pre-surfacing confirmeds, so it
# defaults to a benign "unknown"; it is never required and never invalidates a confirmed. It is
# a self-report, so cross-check it against the SAME field on the chained review.verdict event
# (which the witness binding already authenticated): a match makes the label chain-consistent;
# a mismatch is surfaced as a WARNING so a second party is not silently misled.
_we_mode = we.get("w3_mode") or "unknown"
_ve = by_hash.get(we.get("verdict_event")) if isinstance(we.get("verdict_event"), str) else None
_ve_mode = ((_ve or {}).get("witness_evidence") or {}).get("w3_mode") or "unknown"
_mode_note = "" if _we_mode == _ve_mode else " (WARNING: verdict event records '%s' — mismatch)" % _ve_mode

print("AUDIT PASS (%s): witness-bound %s, re-verified from repo + log" % (pid, grade))
print("  grade         : %s" % grade)
print("  w3_mode       : %s%s" % (_we_mode, _mode_note))
print("  feature_sha   : %s" % we.get("feature_sha"))
print("  verdict_event : %s" % we.get("verdict_event"))
print("  w2_hash       : %s" % we.get("w2_hash"))
print("  w3_hash       : %s" % we.get("w3_hash"))
print("  w4_hash       : %s" % we.get("w4_hash"))
sys.exit(0)
