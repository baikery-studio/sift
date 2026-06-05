#!/usr/bin/env python3
"""sift-harness kernel — append-only, hash-chained event log.

Trust model (spine):
- Every event carries a monotonic `seq`, a `prev_hash` (the prior event's
  `event_hash`), and its own `event_hash` over the canonical content.
- `verify` re-derives every `event_hash`, checks the `prev_hash` chain and the
  `seq` monotonicity → the log is TAMPER-EVIDENT: any edit / insert / reorder /
  delete breaks the chain and is rejected with a line number.
- This is tamper-EVIDENT, not tamper-PROOF (no secret key — deliberately; this
  is a single-operator tool, not an adversarial multi-party system). Witness
  provenance (see _state.py) is what makes a forged `confirmed` fail.

Stdlib only (no PyYAML / no deps) so it runs on any python3 — part of H8.
"""
import sys, os, json, hashlib, fcntl, unicodedata

GENESIS = "0" * 64


def _canon(obj):
    # NFC-normalize so equal-looking unicode (NFD vs NFC) hashes identically —
    # defense-in-depth for the chain's content hash.
    return unicodedata.normalize("NFC", json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False))


def _event_hash(content):
    # content must NOT contain event_hash
    return hashlib.sha256(_canon(content).encode("utf-8")).hexdigest()


def _read_events(log_path):
    if not os.path.exists(log_path):
        return []
    out = []
    with open(log_path, "r") as f:
        for ln in f:
            if ln.strip():
                out.append(ln.rstrip("\n"))
    return out


def cmd_append(log_path):
    """Reads the new event's fields from env, appends a chained line, prints event_hash.

    The read-last-then-append is serialized under an exclusive advisory lock
    (flock) on a sidecar .lock file, so concurrent appends (e.g. a PostToolUse
    hook racing the pipeline) cannot mint two events with the same seq/prev_hash
    and corrupt the trust substrate. Whole critical section, not just the write.
    """
    d = os.path.dirname(log_path)
    if d and not os.path.isdir(d):
        os.makedirs(d, exist_ok=True)
    lock_path = log_path + ".lock"
    with open(lock_path, "w") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            lines = _read_events(log_path)
            if lines:
                last = json.loads(lines[-1])
                seq = last["seq"] + 1
                prev_hash = last["event_hash"]
            else:
                seq, prev_hash = 1, GENESIS

            we = os.environ.get("SIFT_WITNESS_JSON", "").strip()
            content = {
                "seq": seq,
                "ts": os.environ.get("SIFT_TS", ""),
                "packet_id": os.environ["SIFT_PACKET"],
                "kind": os.environ["SIFT_KIND"],
                "from": os.environ.get("SIFT_FROM", ""),
                "to": os.environ.get("SIFT_TO", ""),
                "actor": os.environ.get("SIFT_ACTOR", "harness"),
                "witness_evidence": json.loads(we) if we else None,
                "prev_hash": prev_hash,
            }
            content["event_hash"] = _event_hash(content)
            with open(log_path, "a") as f:
                f.write(_canon(content) + "\n")
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)
    print(content["event_hash"])


def cmd_verify(log_path):
    prev_hash, prev_seq = GENESIS, 0
    n = 0
    for i, ln in enumerate(_read_events(log_path), 1):
        n = i
        try:
            ev = json.loads(ln)
        except Exception as e:
            sys.stderr.write("log corrupt at line %d: not JSON (%s)\n" % (i, e)); sys.exit(20)
        stored = ev.get("event_hash")
        content = {k: v for k, v in ev.items() if k != "event_hash"}
        if _event_hash(content) != stored:
            sys.stderr.write("log TAMPERED at line %d: event_hash mismatch\n" % i); sys.exit(21)
        if ev.get("prev_hash") != prev_hash:
            sys.stderr.write("chain BROKEN at line %d: prev_hash != prior event_hash\n" % i); sys.exit(22)
        if ev.get("seq") != prev_seq + 1:
            sys.stderr.write("seq BROKEN at line %d: expected %d, got %s\n" % (i, prev_seq + 1, ev.get("seq"))); sys.exit(23)
        prev_hash, prev_seq = stored, ev["seq"]
    print("chain ok: %d events" % n)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.stderr.write("usage: _log.py {append|verify} <log_path>\n"); sys.exit(2)
    cmd, log_path = sys.argv[1], sys.argv[2]
    if cmd == "append":
        cmd_append(log_path)
    elif cmd == "verify":
        cmd_verify(log_path)
    else:
        sys.stderr.write("unknown cmd: %s\n" % cmd); sys.exit(2)
