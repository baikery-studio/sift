#!/usr/bin/env bash
# selftest: multi-host adapters are valid AND in sync with the canonical source.
# Regenerating into a temp tree must byte-match the tracked adapters (anti-drift), and
# the engine must run from each layout. Re-run `sift sync` to fix any drift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }

# 1. host manifests are valid JSON
for f in opencode/opencode.json .codex-plugin/plugin.json .cursor-plugin/plugin.json .claude-plugin/marketplace.json; do
  python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$ROOT/$f" || fail "$f invalid JSON"
done

# 2. anti-drift: regenerate into a throwaway SIFT_PLUGIN_ROOT copy and diff the adapters
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -R "$ROOT/." "$tmp/" 2>/dev/null || true
rm -rf "$tmp/opencode" "$tmp/.codex-plugin" "$tmp/codex" "$tmp/.cursor" "$tmp/.cursor-plugin" "$tmp/hermes" "$tmp/plugins/sift-harness"
SIFT_PLUGIN_ROOT="$tmp" bash "$ROOT/kernel/sync.sh" >/dev/null 2>&1 || fail "sift sync failed"
for d in opencode .codex-plugin codex .cursor .cursor-plugin hermes plugins/sift-harness; do
  diff -r "$ROOT/$d" "$tmp/$d" >/dev/null 2>&1 || fail "$d/ has drifted from canonical source — run 'sift sync' and commit"
done

# 3. each non-Claude command adapter exists for every canonical verb
for f in "$ROOT"/commands/sift-*.md; do
  v="$(basename "$f" .md | sed 's/^sift-//')"
  [ -f "$ROOT/opencode/command/sift-$v.md" ] || fail "opencode missing command sift-$v"
done

# 4. engine runs by path from a foreign cwd (host-agnostic core)
w="$(mktemp -d)"; ( cd "$w" && SIFT_REPO_ROOT="$w" bash "$ROOT/bin/sift" version >/dev/null ) || fail "engine did not run by path"; rm -rf "$w"

# 4b. hermes skill frontmatter must be valid YAML (the canonical description has embedded
#     quotes — they must be escaped, or hermes's parser breaks).
python3 - "$ROOT/hermes/skills/sift-workflow/SKILL.md" <<'PY' || fail "hermes SKILL.md frontmatter not valid YAML (escape the description quotes)"
import sys, re, json
t = open(sys.argv[1]).read(); m = re.match(r'^---\n(.*?)\n---', t, re.S)
assert m, "no frontmatter"
for ln in m.group(1).splitlines():
    mm = re.match(r'^description:\s*(.*)$', ln)
    if mm and mm.group(1).startswith('"'):
        json.loads(mm.group(1))   # a JSON string is a valid YAML double-quoted scalar; raises if malformed
PY

# 5. HOSTS.md is honest: engine-everywhere, hooks are optional Claude-Code-only, and the
#    non-Claude live-install stays honestly not-observed.
grep -qiE 'optional.*(claude code|hook)|hooks?.*(claude code only|not part of the engine)' "$ROOT/docs/spec/HOSTS.md" || fail "HOSTS.md must frame the scope-guard/resume hooks as optional Claude-Code-only (not part of the engine)"
grep -qiE 'operator-attested|not yet observed|not_observed' "$ROOT/docs/spec/HOSTS.md" || fail "HOSTS.md must keep non-Claude live-install honestly not-observed"

echo "PASS: host manifests valid, adapters in sync with canonical (anti-drift), engine runs by path, HOSTS.md honest"
