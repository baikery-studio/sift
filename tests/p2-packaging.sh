#!/usr/bin/env bash
# selftest: the plugin manifest, marketplace, hooks wiring, command surface, and
# onboarding files exist and are well-formed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in plugins/sift-harness/.claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$ROOT/$f" \
    || { echo "$f is not valid JSON"; exit 1; }
done
grep -q 'pretooluse-scope.sh' "$ROOT/hooks/hooks.json" || { echo "hooks.json does not wire the scope guard"; exit 1; }
# Claude Code load contract (verified live against 2.1.161): hooks/hooks.json MUST be a
# {"hooks": {...}} record — CC's loader reads file.hooks, so a flat event map yields
# "expected record, received undefined" and the plugin fails to load. And the bundle
# plugin.json MUST NOT declare "commands"/"hooks": CC auto-discovers commands/ and
# hooks/hooks.json, so declaring them double-registers and fails the load.
for hj in "$ROOT/hooks/hooks.json" "$ROOT/plugins/sift-harness/hooks/hooks.json"; do
  [ -f "$hj" ] || continue
  python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
h=d.get("hooks")
assert isinstance(h,dict), "hooks.json must wrap events under a top-level \"hooks\" record (CC reads file.hooks)"
# HERD wave: the full live-steering lifecycle must stay wired via ${CLAUDE_PLUGIN_ROOT}.
need={"PreToolUse":"pretooluse-scope.sh","SessionStart":"sessionstart.sh","Stop":"stop-block.sh",
      "UserPromptSubmit":"userprompt-reinject.sh","PostToolUse":"posttool-reset.sh"}
for ev,scr in need.items():
    assert ev in h, "hooks.hooks missing %s" % ev
    blob=json.dumps(h[ev])
    assert scr in blob, "%s does not invoke %s" % (ev,scr)
    assert "CLAUDE_PLUGIN_ROOT" in blob, "%s not wired via ${CLAUDE_PLUGIN_ROOT}" % ev' "$hj" \
    || { echo "$hj does not wire the full HERD hook lifecycle"; exit 1; }
done
python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
assert "commands" not in d and "hooks" not in d, "bundle plugin.json must NOT declare commands/hooks (auto-discovered; declaring them fails the CC load)"' \
  "$ROOT/plugins/sift-harness/.claude-plugin/plugin.json" \
  || { echo "bundle plugin.json must not declare commands/hooks"; exit 1; }
for v in plan execute review next doctor new; do
  [ -f "$ROOT/commands/sift-$v.md" ] || { echo "missing command sift-$v.md"; exit 1; }
  grep -q 'CLAUDE_PLUGIN_ROOT' "$ROOT/commands/sift-$v.md" || { echo "sift-$v.md hardcodes a path"; exit 1; }
done
[ -f "$ROOT/README.md" ] && [ -f "$ROOT/LICENSE" ] || { echo "README.md/LICENSE missing"; exit 1; }
# manifest schema shape: marketplace owner must be an OBJECT (a string owner risks a
# strict-install rejection); every listed plugin needs name+source; plugin.json
# version must match VERSION (and marketplace metadata.version if present).
python3 - "$ROOT/.claude-plugin/marketplace.json" "$ROOT/plugins/sift-harness/.claude-plugin/plugin.json" "$ROOT/VERSION" <<'PY' \
  || { echo "manifest schema-shape check failed"; exit 1; }
import json, sys
mkt = json.load(open(sys.argv[1])); plg = json.load(open(sys.argv[2]))
ver = open(sys.argv[3]).read().strip()
o = mkt.get("owner")
assert isinstance(o, dict) and o.get("name"), "marketplace owner must be an object with a name"
plugins = mkt.get("plugins") or []
assert plugins, "marketplace must list at least one plugin"
for pl in plugins:
    assert pl.get("name") and pl.get("source"), "each marketplace plugin needs name + source"
    # source must be a RECOGNIZED form, else Claude Code rejects with "source type not
    # supported". Ground truth from plugins installed on CC 2.1.161: the working forms are
    # a relative-path STRING ("./plugins/<name>") or a `url`/`github` OBJECT; a bare '.' is
    # never installable. (git-subdir is catalog-listed but was not installable on 2.1.161.)
    src = pl["source"]
    if isinstance(src, str):
        assert src.startswith("./") or src.startswith("/"), \
            "plugin source %r is not a path form (a bare '.' is not valid; use './')" % src
    else:
        assert isinstance(src, dict) and src.get("source"), "object source needs a 'source' type"
assert plg.get("name") and plg.get("version"), "plugin.json needs name + version"
assert plg["version"] == ver, "plugin.json version (%s) != VERSION (%s)" % (plg["version"], ver)
mver = (mkt.get("metadata") or {}).get("version")
assert mver is None or mver == ver, "marketplace metadata.version (%s) != VERSION (%s)" % (mver, ver)
PY
echo "PASS: plugin manifest + marketplace + hooks + /sift-* commands + README/LICENSE present and well-formed; owner-object + name/source + version-lockstep"
