#!/usr/bin/env bash
# kernel/sync.sh — `sift sync`: generate the per-host adapter trees from ONE canonical
# source (commands/ + skills/ + the bin/sift verb surface), so multi-host support never
# becomes N drifting hand-maintained copies. Re-run after changing commands/ or the
# skill; the p8-multihost selftest fails if a tracked adapter drifts from this output.
#
# The ENGINE (bin/sift + kernel + profiles + the witness-bound trust core) is host-
# agnostic and identical everywhere. Only this thin adapter layer (how a host discovers
# the verbs + wires hooks) differs. Capability degrades per host — see docs/spec/HOSTS.md:
#   Claude Code : commands + hooks (PreToolUse scope guard + SessionStart resume) + skill   FULL
#   opencode    : commands + skill + AGENTS instructions                                     commands+skill
#   Cursor      : rules + AGENTS + candidate hooks                                           guidance(+hooks)
#   Codex       : skill route + AGENTS instructions (NO PreToolUse → scope guard advisory)   skill-only
set -euo pipefail
_SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${SIFT_PLUGIN_ROOT:-$(cd "$_SYNC_DIR/.." && pwd)}"
VER="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)"

# canonical verb list + descriptions, derived from commands/*.md (single source of truth)
_verbs() { for f in "$ROOT"/commands/sift-*.md; do basename "$f" .md | sed 's/^sift-//'; done; }
_desc()  { sed -n 's/^description: *//p' "$ROOT/commands/sift-$1.md" 2>/dev/null | head -1; }

# shared AGENTS instruction block (hosts that drive the engine by path, not a plugin root)
_agents_md() {
  local host="$1"
  cat <<EOF
# sift-harness — $host adapter

sift-harness enforces **plan → execute → review** rigor: every unit of work is a
hash-pinned *packet* driven to a witness-bound \`confirmed\` through an append-only,
tamper-evident log — so an agent can't declare work premature, unwired, or forged.

The engine is host-agnostic. From this repo, drive it with \`bin/sift\`:

\`\`\`
SIFT_REPO_ROOT="\$(pwd)" bash <SIFT_HOME>/bin/sift <verb> [args]
\`\`\`
where \`<SIFT_HOME>\` is where this plugin is installed/cloned.

Verbs: $(_verbs | tr '\n' ' ')+ state status verify-log selftest setup wave-review focus packet.

The loop: \`packet new\` → produce the artifact → \`plan\` → \`execute\` → \`review\` → \`confirmed\`.

> Capability on $host: see docs/spec/HOSTS.md. The witness-bound trust core works here
> via \`bin/sift\`. Runtime scope-guard *enforcement* requires a PreToolUse-style hook;
> where the host lacks one, the scope guard is advisory (guidance), not enforced.
EOF
}

# ---- opencode: commands + skill + opencode.json + AGENTS.md --------------------------
_sync_opencode() {
  local d="$ROOT/opencode"; mkdir -p "$d/command" "$d/skill/sift-workflow"
  cat > "$d/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["AGENTS.md"],
  "permission": { "skill": { "*": "allow" } }
}
EOF
  _agents_md opencode > "$d/AGENTS.md"
  cp "$ROOT/skills/sift-workflow/SKILL.md" "$d/skill/sift-workflow/SKILL.md"
  local v
  for v in $(_verbs); do
    cat > "$d/command/sift-$v.md" <<EOF
---
description: $(_desc "$v")
---
Run \`SIFT_REPO_ROOT="\$(pwd)" bash "\$SIFT_HOME/bin/sift" $v \$ARGUMENTS\` from the repo
root and report the result. (\`\$SIFT_HOME\` = the sift-harness install path; see AGENTS.md.)
EOF
  done
}

# ---- codex: skills route + AGENTS (no hooks; scope guard advisory) -------------------
_sync_codex() {
  mkdir -p "$ROOT/.codex-plugin" "$ROOT/codex"
  cat > "$ROOT/.codex-plugin/plugin.json" <<EOF
{
  "name": "sift-harness",
  "version": "$VER",
  "description": "plan→execute→review rigor for Codex CLI: hash-pinned packets, witness-bound confirmation, compaction-survival resume (scope guard is advisory on Codex — no PreToolUse hook).",
  "license": "MIT",
  "keywords": ["codex", "harness", "verification", "plan-work-review"],
  "skills": "../skills/",
  "interface": {
    "displayName": "sift-harness",
    "shortDescription": "Witness-bound plan→execute→review for Codex CLI",
    "category": "Coding",
    "capabilities": ["Read", "Write", "Interactive"]
  }
}
EOF
  _agents_md "Codex CLI" > "$ROOT/codex/AGENTS.md"
}

# ---- cursor: rule + AGENTS + candidate hooks + plugin manifest -----------------------
_sync_cursor() {
  mkdir -p "$ROOT/.cursor/rules" "$ROOT/.cursor-plugin"
  cat > "$ROOT/.cursor-plugin/plugin.json" <<EOF
{
  "name": "sift-harness",
  "version": "$VER",
  "description": "Candidate Cursor adapter for sift-harness plan→execute→review rigor.",
  "license": "MIT",
  "keywords": ["cursor", "harness", "verification"]
}
EOF
  _agents_md Cursor > "$ROOT/.cursor/AGENTS.md"
  # Cursor rule (.mdc): always-applied guidance pointing at the engine
  cat > "$ROOT/.cursor/rules/sift-workflow.mdc" <<EOF
---
description: sift-harness plan→execute→review workflow (witness-bound completion)
alwaysApply: true
---
Use the sift-harness loop for rigor-warranting work: scaffold a packet, produce its
artifact, then \`bash "\$SIFT_HOME/bin/sift" plan|execute|review <id>\` to drive it to a
witness-bound \`confirmed\`. The append-only hash-chained log is the source of truth;
do not hand-edit \`.harness/\`. See AGENTS.md and docs/spec/HOSTS.md (Cursor tier).
EOF
}

# ---- hermes (Nous Research agent): agentskills.io skill route + AGENTS -----------------
# Hermes loads skills from ~/.hermes/skills/<name>/SKILL.md (HERMES_SKILL_DIR) and reads
# AGENTS.md. HERMES_ACCEPT_HOOKS is an auto-accept toggle for hermes's OWN hooks, NOT a
# pluggable external pre-tool gate — so the sift scope guard is ADVISORY on hermes.
_sync_hermes() {
  local d="$ROOT/hermes/skills/sift-workflow"; mkdir -p "$d"
  local desc; desc="$(sed -n 's/^description: *//p' "$ROOT/skills/sift-workflow/SKILL.md" | head -1)"
  # JSON-encode the description → a valid YAML double-quoted flow scalar (handles the
  # embedded quotes in the canonical description, which would otherwise break YAML).
  local descq; descq="$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1],ensure_ascii=False))' "$desc")"
  # hermes-flavored frontmatter (name/description/version/platforms/metadata.hermes.tags)
  # wrapping the canonical skill BODY (everything after the source frontmatter) so the
  # guidance stays single-source.
  {
    printf -- '---\n'
    printf 'name: sift-workflow\n'
    printf 'description: %s\n' "$descq"
    printf 'version: %s\n' "$VER"
    printf 'platforms: [linux, macos, windows]\n'
    printf 'metadata:\n  hermes:\n    tags: [sift, harness, plan-execute-review, witness, packet, verify]\n'
    printf -- '---\n'
    awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{f=0;next} !f' "$ROOT/skills/sift-workflow/SKILL.md"
  } > "$d/SKILL.md"
  _agents_md "Hermes Agent" > "$ROOT/hermes/AGENTS.md"
}

# ---- Claude Code marketplace bundle: SELF-CONTAINED plugin in plugins/sift-harness/ ----
# CC copies ONLY the plugin subdir to its cache and forbids ${CLAUDE_PLUGIN_ROOT}/../..
# path-traversal (verified against CC docs), so the engine must be BUNDLED inside the
# plugin dir. We generate that bundle from the canonical root tree; marketplace.json (at
# repo root) points to it. The root tree stays the dev/CLI/multi-host source.
_sync_claude_bundle() {
  local b="$ROOT/plugins/sift-harness"
  rm -rf "$b"; mkdir -p "$b/.claude-plugin"
  # runtime plugin only (engine + Claude Code adapter) — NOT dev artifacts
  # (tests/evals/tasks/benchmarks/docs/other-host adapters stay at root).
  local item
  for item in bin kernel profiles commands hooks skills; do
    cp -R "$ROOT/$item" "$b/$item"
  done
  rm -rf "$b"/kernel/__pycache__ "$b"/profiles/*/__pycache__ 2>/dev/null || true
  cp "$ROOT/VERSION" "$b/VERSION"
  [ -f "$ROOT/LICENSE" ] && cp "$ROOT/LICENSE" "$b/LICENSE"
  # the plugin manifest lives INSIDE the bundle (CLAUDE_PLUGIN_ROOT = the bundle dir;
  # hooks/commands call ${CLAUDE_PLUGIN_ROOT}/bin/sift, correctly resolved).
  # NO "commands"/"hooks" fields: Claude Code AUTO-DISCOVERS commands/ and hooks/hooks.json.
  # Declaring them duplicates the auto-loaded standard files and fails the load
  # ("Duplicate hooks file ... should only reference ADDITIONAL hook files"). hooks/hooks.json
  # itself must be a {"hooks": {...}} record (CC parses file.hooks), not a flat event map.
  cat > "$b/.claude-plugin/plugin.json" <<EOF
{
  "name": "sift-harness",
  "version": "$VER",
  "description": "Enforces plan→execute→review rigor: every unit of work is a hash-pinned packet driven to a witness-bound confirmed through an append-only tamper-evident log, so agents can't declare premature, unwired, or forged completion.",
  "author": { "name": "sift-harness contributors" },
  "license": "MIT",
  "keywords": ["agent", "harness", "verification", "long-horizon", "scope-guard", "provenance"]
}
EOF
}

sift_sync() {
  _sync_opencode
  _sync_codex
  _sync_cursor
  _sync_hermes
  _sync_claude_bundle
  echo "[sift] synced host adapters (opencode, codex, cursor, hermes) + the Claude Code"
  echo "[sift] marketplace bundle (plugins/sift-harness/) from canonical source @ v$VER"
}

if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then sift_sync "$@"; fi
