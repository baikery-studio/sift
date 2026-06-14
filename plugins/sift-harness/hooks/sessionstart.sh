#!/usr/bin/env bash
# hooks/sessionstart.sh — host lifecycle adapter (criterion 5: long-horizon).
# A fresh session (cold start, or resume after a context compaction) carries NO
# in-memory state. This adapter recomputes the wave's resume point FROM THE LOG
# and prints it for the host to inject into the new context window.
#
# Wiring: installed as a plugin, hooks/hooks.json registers this on SessionStart
# via ${CLAUDE_PLUGIN_ROOT}. Manual (non-plugin) form in .claude/settings.json,
# co-located in the repo:
#     {"hooks":{"SessionStart":[{"hooks":[{"type":"command",
#        "command":"${CLAUDE_PLUGIN_ROOT}/hooks/sessionstart.sh phase1"}]}]}}
# A PreCompact entry (same command) is OPTIONAL/Planned — PreCompact stdout is not
# injected the way SessionStart additionalContext is, so it may be a no-op there.
#   Other CLIs   wire to their session-init equivalent.
#
# Idempotent and side-effect-free: it reads the log, writes nothing.
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SIFT="$HOOK_DIR/../bin/sift"
# `--precompact <wave>`: PreCompact stdout is NOT injected like SessionStart
# additionalContext, so on PreCompact we persist a resume breadcrumb to disk that the
# next SessionStart reads. Best-effort durability — closes the one inject-window.
precompact=0
if [ "${1:-}" = "--precompact" ]; then precompact=1; shift; fi
wid="${1:-phase1}"

# Resolve the repo root the way a host actually invokes a hook: it may run from
# an arbitrary cwd, so honor CLAUDE_PROJECT_DIR (Claude Code), then an explicit
# SIFT_REPO_ROOT, before falling back to cwd. Export so bin/sift inherits it.
export SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-${SIFT_REPO_ROOT:-$(pwd)}}"

# SOTA-2: the EXPLICIT agent-host signal. A SessionStart hook only fires inside a live agent
# host, so its execution IS proof an agent is present — set the generic, host-agnostic marker
# (not inferred from any ambient dir) so the default W3 regime becomes the host-written R1-R13
# review. On a host that propagates hook env into the session shell this reaches `sift review`
# directly; where it does not, the same default is reachable via SIFT_W3_REQUIRE_HOST_VERDICT=1
# or the profile flag. SIFT_W3_HOST_VERDICT=off opts back out. Never keyed off CLAUDE_PROJECT_DIR
# (CI exports it) so the keyless offline/CI path and the selftest stay unchanged.
export SIFT_AGENT_HOST=1

next="$("$SIFT" next "$wid" 2>/dev/null || echo UNKNOWN)"

BREADCRUMB="$SIFT_REPO_ROOT/.harness/resume.breadcrumb"
if [ "$precompact" = 1 ]; then
  mkdir -p "$SIFT_REPO_ROOT/.harness" 2>/dev/null || true
  printf 'wave=%s\nnext=%s\n' "$wid" "$next" > "$BREADCRUMB" 2>/dev/null || true
  echo "[sift] precompact: wrote resume breadcrumb (wave '$wid' → $next)"
  exit 0
fi
# Only speak in a repo that is actually sift-set-up. In every other project the plugin
# stays silent — no noise. `sift setup` (or the first packet) is the opt-in signal; this
# is the plugin-native equivalent of a repo CLAUDE.md "use the harness" standing rule.
if [ ! -f "$SIFT_REPO_ROOT/sift-harness.config.json" ] && [ ! -d "$SIFT_REPO_ROOT/.harness" ]; then
  exit 0
fi

# FORT-1 engage-gate: reset the freehand-edit detector per session, so a stale marker from a
# prior session never blocks a fresh one. (config.sh gives the real state dir; fall back to
# .harness, matching the breadcrumb path above.)
. "$HOOK_DIR/../kernel/config.sh" 2>/dev/null || true
SIFT_STATE="${SIFT_STATE:-$(config_path state 2>/dev/null || echo "$SIFT_REPO_ROOT/.harness")}"
rm -f "$SIFT_STATE/unpacketed-edit" 2>/dev/null || true
# ENGAGE-COLD-1: same per-session reset for the cold-repo engage marker. Reached only once
# .harness/ exists (the line-44 guard skips a truly-untouched cold repo — which has no marker
# to reset anyway). The case that matters: a repo cold-edited in a PRIOR session armed the
# marker AND created .harness/, so a fresh edit-free session here resets it and ends freely —
# the gate is armed by an edit this session, not by lingering coldness.
rm -f "$SIFT_STATE/cold-engage" 2>/dev/null || true

# Standing primer (injected once per session as additionalContext): point the agent at the
# harness as the law of this repo, so "use the harness" / any rigor-worthy task drives the
# loop instead of being freehanded.
cat <<'PRIMER'
[sift-harness active in this repo]
For any multi-step change, a fix that must be verified, or anything you must not call
"done" prematurely: drive it through sift rather than freehanding it.
  - Use the `sift-workflow` skill (or the `/sift-harness:sift-*` commands) to run the loop:
    scaffold a packet -> plan -> execute -> review -> witness-bound `confirmed`.
  - Completion is witness-bound: do NOT report a task done until `sift state <id>` is
    `confirmed`. The Stop hook blocks ending the turn while a packet is unconfirmed.
PRIMER

# normal SessionStart: surface a prior PreCompact breadcrumb if one exists
if [ -f "$BREADCRUMB" ]; then
  echo "[sift] (breadcrumb) $(tr '\n' ' ' < "$BREADCRUMB")"
fi

if [ "$next" = "ALL-CONFIRMED" ]; then
  echo "[sift] wave '$wid': all packets confirmed — nothing in flight. Run \`sift wave-review $wid\` to gate."
elif [ "$next" = "UNKNOWN" ]; then
  echo "[sift] wave '$wid': no resume point (no manifest or empty log)."
else
  st="$("$SIFT" state "$next" 2>/dev/null || echo submitted)"
  # suggest the verb that's actually valid from the current state (suggesting
  # `sift execute` on a `submitted` packet errors — plan must run first).
  case "$st" in
    submitted)              cont="sift plan $next" ;;
    packeted|failed|review_failed) cont="sift execute $next" ;;
    acceptance_met)         cont="sift review $next" ;;
    *)                      cont="sift plan $next && sift execute $next && sift review $next" ;;
  esac
  echo "[sift] RESUME wave '$wid' → next actionable packet: $next (state: $st). Continue with: $cont"
fi
