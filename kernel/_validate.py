#!/usr/bin/env python3
"""sift-harness kernel — validate a SIFT packet's schema (stdlib only, no PyYAML).

  _validate.py <packet_md> <plugin_root>   exit 0 valid, 1 invalid (errors to stderr)

SIFT packets (profile/goal/artifact) are a DIFFERENT schema from the donor engine's
packets (objective/...). The donor's validate_packet rejects sift keys as unknown,
so sift validates its own. Checks: required top-level keys, the profile exists, and
the per-profile required fields — DRIVEN BY THE PROFILE'S OWN `task_schema` (in
profile.json), NOT hardcoded here. The kernel stays profile-agnostic: a new profile
declares its required fields in its task_schema and validation follows, zero edits here.
"""
import sys, os, re, json

pkt, plug = sys.argv[1], sys.argv[2]
try:
    with open(pkt, encoding="utf-8") as _f:
        text = _f.read()
except OSError as e:
    sys.stderr.write("cannot read packet: %s\n" % e); sys.exit(1)
m = re.match(r"^---\s*\n(.*?)\n---", text, re.S)
if not m:
    sys.stderr.write("no YAML frontmatter\n"); sys.exit(1)
fm = m.group(1)


def top(key):
    for ln in fm.splitlines():
        mm = re.match(r"^" + re.escape(key) + r":\s*(.*)$", ln)
        if mm:
            v = mm.group(1).strip().strip('"').strip("'")
            return v if v else "_block"   # key present with a block/empty value (still "present")
    return None


def nested(parent, key):
    inp = False
    for ln in fm.splitlines():
        if re.match(r"^" + re.escape(parent) + r":\s*$", ln):
            inp = True; continue
        if inp:
            if re.match(r"^\S", ln):
                break
            mm = re.match(r"^\s+" + re.escape(key) + r":\s*(.*)$", ln)
            if mm:
                return mm.group(1).strip().strip('"').strip("'")
    return None


def scope_has_paths():
    inp = inpaths = False
    for ln in fm.splitlines():
        if re.match(r"^scope:\s*$", ln):
            inp = True; continue
        if inp:
            if re.match(r"^\S", ln):
                break
            if re.match(r"^\s+paths:\s*$", ln):
                inpaths = True; continue
            if inpaths and re.match(r"^\s+-\s+\S", ln):
                return True
    return False


errs = []
for k in ("schema_version", "id", "profile", "goal", "proof_artifact"):
    if not top(k):
        errs.append("missing required key: %s" % k)
if not scope_has_paths():
    errs.append("scope.paths must list at least one path")

def _load_task_schema(prof_dir):
    """Return the profile's task_schema as a dict, or None. Handles both forms:
    an inline object in profile.json, or a string path to a JSON-Schema file."""
    try:
        with open(os.path.join(prof_dir, "profile.json")) as f:
            ts = json.load(f).get("task_schema")
    except (OSError, ValueError):
        return None
    if isinstance(ts, str):
        # resolve the schema file relative to the profile dir and CONTAIN it there —
        # a task_schema path must not escape the profile (defense-in-depth; profile.json
        # is committed code, but never follow a path/symlink out of the profile).
        rel = ts[2:] if ts.startswith("./") else ts
        base = os.path.realpath(prof_dir)
        full = os.path.realpath(os.path.join(base, rel))
        if full != base and not full.startswith(base + os.sep):
            return None
        try:
            with open(full) as f:
                return json.load(f)
        except (OSError, ValueError):
            return None
    return ts if isinstance(ts, dict) else None


def _present(key):
    """Is a top-level OR dotted-nested key present in the frontmatter?"""
    if "." in key:
        parent, child = key.split(".", 1)
        return nested(parent, child) is not None
    return top(key) is not None


def _required_keys(schema):
    """Flatten a task_schema's required fields into checkable (possibly dotted) keys.
    Supports the flat form {required:[...]} and JSON-Schema {required:[...],
    properties:{X:{required:[...]}}} (→ X.child). NOTE: only top-level + one level of
    object nesting (X.child); a deeper schema (X.y.z) would need recursive flattening."""
    out = []
    for k in schema.get("required", []) or []:
        out.append(k)
        sub = (schema.get("properties", {}) or {}).get(k, {})
        if isinstance(sub, dict):
            for c in sub.get("required", []) or []:
                out.append("%s.%s" % (k, c))
    return out


profile = top("profile")
if profile:
    if "/" in profile or ".." in profile:   # a profile is a name, not a path
        errs.append("profile must not contain path separators: %s" % profile)
    else:
        prof_dir = os.path.join(plug, "profiles", profile)
        if not os.path.isdir(prof_dir):
            errs.append("unknown profile: %s (no profiles/%s/)" % (profile, profile))
        else:
            schema = _load_task_schema(prof_dir)
            if schema is None:
                errs.append("profile %s has no readable task_schema in profile.json" % profile)
            else:
                # the generic top-level keys (id/profile/goal/...) are already checked
                # above; here enforce the profile's OWN declared required fields.
                for rk in _required_keys(schema):
                    if rk in ("id", "profile", "goal"):
                        continue   # already covered by the generic required-key loop
                    if not _present(rk):
                        errs.append("profile %s requires %s (per its task_schema)" % (profile, rk))

if errs:
    for e in errs:
        sys.stderr.write("invalid packet: %s\n" % e)
    sys.exit(1)
print("valid packet: %s (profile %s)" % (top("id"), profile))
