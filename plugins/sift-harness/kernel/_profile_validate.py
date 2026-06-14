#!/usr/bin/env python3
"""Validate a profile.json against the documented profile contract (stdlib only).

The kernel dispatches profiles by path convention, but PROFILE_INTERFACE.md documents
a profile.json schema. This validator makes the documented schema ENFORCED at load:
a profile with a malformed/garbage manifest fails closed (the kernel refuses to
dispatch it) rather than the manifest being silently ignored.

Checks (fail closed = exit 2 with a reason on stderr):
  - valid JSON object
  - required keys with correct types: name (str), kernel_version (str),
    task_schema (str|object), acceptance (object), witnesses (object)
  - soft_floors, if present, is a list
Extra top-level keys (e.g. "description") are allowed.

Usage: _profile_validate.py <path/to/profile.json>   # exit 0 valid, 2 invalid
"""
import json, os, re, sys

_REQUIRED = {
    "name": str,
    "kernel_version": str,
    "task_schema": (str, dict),
    "acceptance": dict,
    "witnesses": dict,
}


def _ver_tuple(s):
    """Parse 'X.Y.Z' (or X.Y) into a comparable int tuple; missing parts default to 0."""
    parts = re.findall(r"\d+", s)
    parts = (parts + ["0", "0", "0"])[:3]
    return tuple(int(p) for p in parts)


def _kernel_version():
    """The running kernel's version from the VERSION file beside the kernel dir."""
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "VERSION")) as f:
            return f.read().strip()
    except OSError:
        return "0.0.0"


def _kernel_satisfies(req):
    """Does this kernel satisfy a profile's kernel_version range? Supports >=, ==, and an
    exact 'X.Y.Z'. Fail OPEN only on an unparseable/empty requirement (treated as 'any')."""
    req = (req or "").strip()
    if not req:
        return True
    kv = _ver_tuple(_kernel_version())
    m = re.match(r"^(>=|==|=)?\s*([0-9][0-9.]*)$", req)
    if not m:
        return True   # unknown form (e.g. a complex range) — do not block on what we can't parse
    op, ver = m.group(1) or "==", _ver_tuple(m.group(2))
    if op == ">=":
        return kv >= ver
    return kv == ver


def validate(path):
    errs = []
    try:
        with open(path) as f:
            d = json.load(f)
    except FileNotFoundError:
        return ["profile.json not found: %s" % path]
    except (ValueError, OSError) as e:
        return ["profile.json is not valid JSON: %s" % e]
    if not isinstance(d, dict):
        return ["profile.json must be a JSON object"]

    for key, typ in _REQUIRED.items():
        if key not in d:
            errs.append("missing required key: %s" % key)
        elif not isinstance(d[key], typ):
            want = typ.__name__ if isinstance(typ, type) else "/".join(t.__name__ for t in typ)
            errs.append("key %s must be %s, got %s" % (key, want, type(d[key]).__name__))

    if "soft_floors" in d and not isinstance(d["soft_floors"], list):
        errs.append("soft_floors must be a list")

    # kernel_version is a COMPATIBILITY RANGE, not just a string: a profile written against a
    # FUTURE kernel must be rejected at load (fail closed), not silently accepted. Supports the
    # simple forms profiles use: ">=X.Y[.Z]", "X.Y[.Z]" (exact), "==X.Y[.Z]".
    kv = d.get("kernel_version")
    if isinstance(kv, str) and not _kernel_satisfies(kv):
        errs.append("kernel_version %r not satisfied by this kernel %s (profile needs a newer kernel)"
                    % (kv, _kernel_version()))

    w = d.get("witnesses")
    if isinstance(w, dict):
        w3 = w.get("w3")
        if w3 is not None and not isinstance(w3, dict):
            errs.append("witnesses.w3 must be an object")
    return errs


def main(argv):
    if not argv:
        sys.stderr.write("usage: _profile_validate.py <profile.json>\n")
        return 2
    errs = validate(argv[0])
    if errs:
        for e in errs:
            sys.stderr.write("profile-invalid: %s\n" % e)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
