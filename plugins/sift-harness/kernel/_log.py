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
LOG_SCHEMA_VERSION = "2"   # "2" = the hash-chained {seq,prev_hash,event_hash} schema


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
            # Torn-last-line repair: a crash mid-append can leave a partial JSON line.
            # Quarantine it (record to <log>.quarantine + drop) and rewrite the log so a
            # single torn tail never permanently bricks all future appends. LAST line only.
            if lines:
                try:
                    json.loads(lines[-1])
                except Exception:
                    torn = lines.pop()
                    with open(log_path + ".quarantine", "a") as q:
                        q.write("torn-tail-quarantined\t" + torn + "\n")
                    with open(log_path, "w") as f:
                        if lines:
                            f.write("\n".join(lines) + "\n")
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
                "log_schema_version": LOG_SCHEMA_VERSION,
            }
            content["event_hash"] = _event_hash(content)
            with open(log_path, "a") as f:
                f.write(_canon(content) + "\n")
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)
    print(content["event_hash"])


def cmd_verify(log_path):
    raw = _read_events(log_path)
    # Classify old-schema ONCE for the WHOLE file (H1 fix): a log is pre-chain only if
    # EVERY event lacks event_hash. A missing event_hash inside an otherwise hash-chained
    # log is TAMPERING (a deleted hash), NOT benign schema drift — so it must not be
    # downgraded to exit 24 (which the operator would "fix" by migrating, laundering the
    # forgery). Parse first; non-JSON is still exit 20.
    evs = []
    for i, ln in enumerate(raw, 1):
        try:
            evs.append(json.loads(ln))
        except Exception as e:
            sys.stderr.write("log corrupt at line %d: not JSON (%s)\n" % (i, e)); sys.exit(20)
    if evs and all(e.get("event_hash") is None for e in evs):
        sys.stderr.write("log schema too old: pre-chain events (no event_hash) — run 'sift migrate-log'\n")
        sys.exit(24)
    prev_hash, prev_seq = GENESIS, 0
    n = 0
    for i, ev in enumerate(evs, 1):
        n = i
        stored = ev.get("event_hash")
        if stored is None:
            # missing hash in a chained log = a deleted hash = TAMPERED (not schema-old).
            sys.stderr.write("log TAMPERED at line %d: event_hash deleted from a chained log\n" % i); sys.exit(21)
        content = {k: v for k, v in ev.items() if k != "event_hash"}
        if _event_hash(content) != stored:
            sys.stderr.write("log TAMPERED at line %d: event_hash mismatch\n" % i); sys.exit(21)
        if ev.get("prev_hash") != prev_hash:
            sys.stderr.write("chain BROKEN at line %d: prev_hash != prior event_hash\n" % i); sys.exit(22)
        if ev.get("seq") != prev_seq + 1:
            sys.stderr.write("seq BROKEN at line %d: expected %d, got %s\n" % (i, prev_seq + 1, ev.get("seq"))); sys.exit(23)
        prev_hash, prev_seq = stored, ev["seq"]
    print("chain ok: %d events" % n)


def cmd_migrate(log_path):
    """Re-chain a pre-chain (old-schema) log into the current hash-chained schema.
    Backs up the original to <log>.pre-migrate; refuses (no-op) if already current;
    never silently drops events. Note: witness_evidence.verdict_event references point
    at OLD hashes, so a migrated `confirmed` needs re-review to re-bind — migration
    restores chain integrity, not witness provenance."""
    lines = _read_events(log_path)
    if not lines:
        print("nothing to migrate: no log at %s" % log_path); return
    parsed = []
    for i, ln in enumerate(lines, 1):
        try:
            parsed.append(json.loads(ln))
        except Exception:
            sys.stderr.write("cannot migrate: line %d is not JSON\n" % i); sys.exit(2)
    have = [bool(e.get("event_hash")) for e in parsed]
    if all(have):
        print("nothing to migrate: log is already current-schema (v%s)" % LOG_SCHEMA_VERSION); return
    if any(have):
        # MIXED log: some events chained, some not. This is NOT benign drift — it is the
        # forgery-laundering shape (a deleted hash inside a chained log). Refuse: migrating
        # would re-chain the tampered event clean. Operator must investigate the tamper.
        sys.stderr.write("cannot migrate: MIXED log (some events hash-chained, some not) — this is a tamper signature, not schema drift; refusing to re-chain. Investigate with 'sift verify-log'.\n")
        sys.exit(2)
    with open(log_path + ".pre-migrate", "w") as f:
        f.write("\n".join(lines) + "\n")
    prev_hash, seq, out = GENESIS, 0, []
    for e in parsed:
        seq += 1
        meta = e.get("metadata") or {}
        content = {
            "seq": seq,
            "ts": e.get("ts", ""),
            "packet_id": e.get("packet_id", ""),
            "kind": e.get("kind", ""),
            "from": e.get("from", meta.get("from", "")),
            "to": e.get("to", meta.get("to", e.get("lane", ""))),
            "actor": e.get("actor", "harness"),
            "witness_evidence": e.get("witness_evidence"),
            "prev_hash": prev_hash,
            "log_schema_version": LOG_SCHEMA_VERSION,
        }
        content["event_hash"] = _event_hash(content)
        out.append(_canon(content))
        prev_hash = content["event_hash"]
    with open(log_path, "w") as f:
        f.write("\n".join(out) + "\n")
    print("migrated %d events to schema v%s (backup: %s.pre-migrate)" % (len(out), LOG_SCHEMA_VERSION, log_path))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.stderr.write("usage: _log.py {append|verify|migrate} <log_path>\n"); sys.exit(2)
    cmd, log_path = sys.argv[1], sys.argv[2]
    if cmd == "append":
        cmd_append(log_path)
    elif cmd == "verify":
        cmd_verify(log_path)
    elif cmd == "migrate":
        cmd_migrate(log_path)
    else:
        sys.stderr.write("unknown cmd: %s\n" % cmd); sys.exit(2)
