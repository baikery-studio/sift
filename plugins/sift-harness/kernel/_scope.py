#!/usr/bin/env python3
"""sift-harness kernel — is a path within a packet's declared scope?

  _scope.py <packet_md> <path>   exit 0 if in scope, 1 if not.

Reads the packet's nested `scope:\\n  paths:\\n    - ...` block with a tiny
stdlib parser (NO PyYAML — portability). Matching mirrors the donor scope_check:
exact, fnmatch glob, "/**" prefix, trailing-"/" dir prefix. Harness state
(.harness/, .canary/) is always DENIED to edit tools (forge prevention — the harness
writes it via bash, which never routes through this guard). A path under SIFT_REPO_ROOT
given as an absolute path is normalized to repo-relative first.
"""
import sys, os, re, fnmatch

HARNESS_PREFIXES = (".harness/", ".canary/")
HARNESS_DIRS = (".harness", ".canary")


def scope_paths(packet_md):
    try:
        text = open(packet_md, encoding="utf-8").read()
    except OSError:
        return []
    m = re.match(r"^---\s*\n(.*?)\n---", text, re.S)
    fm = m.group(1) if m else ""
    paths, in_scope, in_paths = [], False, False
    for ln in fm.splitlines():
        if re.match(r"^scope:\s*$", ln):
            in_scope, in_paths = True, False
            continue
        if in_scope:
            if re.match(r"^\S", ln):           # a new top-level key ends the scope block
                break
            if re.match(r"^\s+paths:\s*$", ln):
                in_paths = True
                continue
            if in_paths:
                mm = re.match(r"^\s+-\s+(.*\S)\s*$", ln)
                if mm:
                    paths.append(mm.group(1).strip().strip('"').strip("'"))
                elif re.match(r"^\s+\S+:", ln):  # another key under scope ends paths
                    in_paths = False
    return paths


def _seg_match(path, pat):
    # fnmatch per path SEGMENT so `*` does NOT cross `/` (`kernel/*.sh` must not
    # match `kernel/sub/x.sh`). Recursive matching is handled by the `/**` branch.
    pp, ps = path.split("/"), pat.split("/")
    if len(pp) != len(ps):
        return False
    return all(fnmatch.fnmatch(a, b) for a, b in zip(pp, ps))


def in_scope(path, paths):
    # HARDEN-HARNESS-WRITE-BOUNDARY: edit-tool writes to harness state (.harness/,
    # .canary/) are DENIED. The harness writes these via BASH (log_append, the review
    # pipeline) which never route through this guard; the ONLY thing that reaches this
    # function for a harness path is an agent's edit tool, and letting it write its own
    # provenance (.harness/reviews/<id>.w3.json, .harness/log.jsonl) is the runtime half
    # of the self-minted-artifact forge. So deny — the inverse of the earlier auto-allow.
    if path in HARNESS_DIRS or any(path.startswith(p) for p in HARNESS_PREFIXES):
        return False
    for pat in paths:
        if path == pat or _seg_match(path, pat):
            return True
        if pat.endswith("/**"):
            pre = pat[:-3]
            if path == pre or path.startswith(pre + "/"):
                return True
        if pat.endswith("/") and (path == pat[:-1] or path.startswith(pat)):
            return True
    return False


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: _scope.py <packet_md> <path>\n"); sys.exit(2)
    pkt, path = sys.argv[1], sys.argv[2]
    root = os.environ.get("SIFT_REPO_ROOT", "")
    if path.startswith("/") and root:
        rr, ap = os.path.realpath(root), os.path.realpath(path)
        if ap == rr or ap.startswith(rr + os.sep):
            path = os.path.relpath(ap, rr)
    if path.startswith("./"):
        path = path[2:]
    path = os.path.normpath(path)   # collapse ../ and ./ so kernel/../kernel/x == kernel/x
    # symlink containment: a relative path that resolves (through symlinks) OUTSIDE
    # the repo is never in scope — a symlink inside a scoped dir can't be an escape.
    if root:
        base = os.path.realpath(root)
        full = os.path.realpath(os.path.join(base, path))
        if full != base and not full.startswith(base + os.sep):
            sys.exit(1)
    sys.exit(0 if in_scope(path, scope_paths(pkt)) else 1)


if __name__ == "__main__":
    main()
