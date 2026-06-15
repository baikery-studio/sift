#!/usr/bin/env python3
"""sift-harness — portable audit-bundle transport (SOTA-1-AUDIT-BUNDLE). Stdlib only.

A bundle is ONE self-describing tar carrying exactly what a second party needs to
replay-verify a witness-bound terminal on a foreign machine, nothing else present:

  log.jsonl           the contiguous hash-chain PREFIX genesis..<terminal event for the
                      packet> — a prefix so `verify_log_chain` still re-derives clean.
  reviews/<id>.w2.json / .w3.json / .w4.json / .packet
                      the bound witness artifacts (+ the pinned packet snapshot).
  bundle.json         {schema, packet_id, feature_sha, chain_head} — the manifest.

Two modes:
  _export.py build   <log> <reviews_dir> <packet_id>   # writes the tar to STDOUT
  _export.py extract <bundle_file>       <out_dir>      # safely unpacks a tar to out_dir
"""
import sys, os, io, json, tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _state import project_state   # refuse to export a packet that does not genuinely verify

TERMINALS = ("confirmed", "partially_confirmed")
SCHEMA = "audit-bundle/v1"


def _events(log_path):
    out = []
    if os.path.exists(log_path):
        for ln in open(log_path):
            if ln.strip():
                try:
                    out.append((ln.rstrip("\n"), json.loads(ln)))
                except Exception:
                    out.append((ln.rstrip("\n"), None))
    return out


def _add_bytes(tar, name, data):
    ti = tarfile.TarInfo(name)
    ti.size = len(data)
    ti.mode = 0o644
    tar.addfile(ti, io.BytesIO(data))


def build(log_path, reviews_dir, packet_id):
    evs = _events(log_path)
    # the LAST terminal lane.transition for this packet bounds the contiguous prefix.
    last_idx, term_ev = -1, None
    for i, (_raw, ev) in enumerate(evs):
        if ev and ev.get("kind") == "lane.transition" and ev.get("to") in TERMINALS \
           and ev.get("packet_id") == packet_id:
            last_idx, term_ev = i, ev
    if last_idx < 0 or term_ev is None:
        sys.stderr.write("export: no witness-bound terminal for '%s' in the log\n" % packet_id)
        return 1
    # refuse to bundle a packet that does not GENUINELY replay to a witness-bound terminal — a
    # corrupt/forged packet has a terminal transition event but project_state replays it corrupt;
    # exporting it would ship a bundle that only fails at audit time (misleading). Verify first.
    if project_state(log_path, packet_id, reviews_dir) not in TERMINALS:
        sys.stderr.write("export: '%s' does not replay to a witness-bound terminal (refusing to bundle)\n" % packet_id)
        return 1
    we = term_ev.get("witness_evidence") or {}
    feature_sha = we.get("feature_sha", "")
    prefix = [raw for raw, _ in evs[:last_idx + 1]]      # genesis..terminal, contiguous
    chain_head = (evs[last_idx][1] or {}).get("event_hash", "")
    log_blob = ("\n".join(prefix) + "\n").encode("utf-8")

    manifest = {"schema": SCHEMA, "packet_id": packet_id,
                "feature_sha": feature_sha, "chain_head": chain_head}

    # collect the bound witness artifacts + the pinned packet snapshot for this packet.
    arts = []
    for suf in (".w2.json", ".w3.json", ".w4.json", ".packet"):
        p = os.path.join(reviews_dir, packet_id + suf)
        if os.path.exists(p):
            with open(p, "rb") as f:
                arts.append(("reviews/" + packet_id + suf, f.read()))

    tar = tarfile.open(fileobj=sys.stdout.buffer, mode="w")
    _add_bytes(tar, "bundle.json", (json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
    _add_bytes(tar, "log.jsonl", log_blob)
    for name, data in arts:
        _add_bytes(tar, name, data)
    tar.close()
    return 0


def _safe_members(tar):
    """Yield only members whose path is relative and contained (no absolute, no `..`, no
    symlink/hardlink/device) — a malicious bundle must not write outside out_dir. Duplicate
    member names are dropped (first wins), so a crafted tar cannot show one bundle.json to
    `tar tf` while a second overwrites it on extract."""
    seen = set()
    for m in tar.getmembers():
        name = m.name
        if name.startswith("/") or ".." in name.replace("\\", "/").split("/"):
            continue
        if not (m.isfile() or m.isdir()):
            continue
        if name in seen:
            continue
        seen.add(name)
        yield m


def extract(bundle_file, out_dir):
    if not os.path.exists(bundle_file):
        sys.stderr.write("extract: bundle not found\n"); return 1
    os.makedirs(out_dir, exist_ok=True)
    out_real = os.path.realpath(out_dir)
    try:
        tar = tarfile.open(bundle_file, mode="r")
    except Exception as e:
        sys.stderr.write("extract: not a readable bundle: %s\n" % e); return 1
    try:
        for m in _safe_members(tar):
            dest = os.path.realpath(os.path.join(out_dir, m.name))
            if dest != out_real and not dest.startswith(out_real + os.sep):
                continue          # belt-and-suspenders containment
            tar.extract(m, out_dir)
    finally:
        tar.close()
    # a valid bundle must carry at least the manifest + log.
    if not os.path.exists(os.path.join(out_dir, "bundle.json")) \
       or not os.path.exists(os.path.join(out_dir, "log.jsonl")):
        sys.stderr.write("extract: bundle missing bundle.json / log.jsonl\n"); return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 5 and sys.argv[1] == "build":
        sys.exit(build(sys.argv[2], sys.argv[3], sys.argv[4]))
    if len(sys.argv) >= 4 and sys.argv[1] == "extract":
        sys.exit(extract(sys.argv[2], sys.argv[3]))
    sys.stderr.write("usage: _export.py build <log> <reviews> <id>  |  extract <bundle> <out_dir>\n")
    sys.exit(2)
