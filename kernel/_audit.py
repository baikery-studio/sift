#!/usr/bin/env python3
"""sift-harness — second-party audit report for a confirmed packet.

  _audit.py <log_path> <packet_id> <reviews_dir>   # exit 0 PASS, 1 FAIL

Assumes the caller already verified the chain and replayed state to `confirmed`
(audit.sh does that via verify-log + project_state, which itself enforces the
witness binding). This re-derives the bound artifact hashes for the explicit,
human-readable verdict report a second party reads: feature_sha + verdict_event +
the W2/W3/W4 artifact hashes, each re-checked against its on-disk file. Stdlib only.
"""
import sys, os, json, hashlib

log_path, pid, reviews = sys.argv[1], sys.argv[2], sys.argv[3]


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


confirmed = None
for e in _events():
    if e.get("kind") == "lane.transition" and e.get("to") == "confirmed" and e.get("packet_id") == pid:
        confirmed = e
if confirmed is None:
    sys.stderr.write("AUDIT FAIL (%s): no confirmed event in the log\n" % pid)
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

print("AUDIT PASS (%s): witness-bound confirmed, re-verified from repo + log" % pid)
print("  feature_sha   : %s" % we.get("feature_sha"))
print("  verdict_event : %s" % we.get("verdict_event"))
print("  w2_hash       : %s" % we.get("w2_hash"))
print("  w3_hash       : %s" % we.get("w3_hash"))
print("  w4_hash       : %s" % we.get("w4_hash"))
sys.exit(0)
