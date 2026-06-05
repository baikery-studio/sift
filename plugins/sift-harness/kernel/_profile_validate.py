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
import json, os, sys

_REQUIRED = {
    "name": str,
    "kernel_version": str,
    "task_schema": (str, dict),
    "acceptance": dict,
    "witnesses": dict,
}


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
