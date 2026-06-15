#!/usr/bin/env bash
# Acceptance for ENGAGE-COLD-1. RED on HEAD: in a repo with no .harness/, posttool-reset.sh
# (lines 67-74) fires the cold branch FIRST — prints a nudge and exit 0 BEFORE arming any
# marker. stop-block.sh:28 blocks only on the `unpacketed-edit` marker (warm repos). So a
# freehand edit in a cold repo leaves nothing to block on and the Stop is ALLOWED. Proves:
# a cold-repo edit arms a gate the Stop hook blocks on (offering setup); no edit -> still
# allowed.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
POST="$ROOT/hooks/posttool-reset.sh"
STOP="$ROOT/hooks/stop-block.sh"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_STATE SIFT_LOG SIFT_PACKETS 2>/dev/null || true

# ---- guard: a COLD repo with NO edit must still allow the stop --------------------------
T0="$(mktemp -d)"; trap 'rm -rf "$T0" "${T:-/nonexistent}"' EXIT   # cold: no .harness/, no config
out0="$(printf '{}' | CLAUDE_PROJECT_DIR="$T0" bash "$STOP" 2>/dev/null || true)"
printf '%s' "$out0" | grep -q '"decision": *"block"' \
  && fail "a cold repo with NO edit blocked the stop (the gate must be armed by an edit, not by coldness)"

# ---- the RED claim: a freehand edit in a cold repo must arm a Stop gate -----------------
T="$(mktemp -d)"   # fresh cold repo: no .harness/, no sift-harness.config.json
[ ! -d "$T/.harness" ] || fail "scaffold broken: temp repo is not cold"
# live PostToolUse on a real edit
printf '{"tool_name":"Edit","tool_input":{"file_path":"foo.txt"}}' \
  | CLAUDE_PROJECT_DIR="$T" bash "$POST" >/dev/null 2>&1 || true
# now try to end the turn
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$T" bash "$STOP" 2>/dev/null || true)"
printf '%s' "$out" | grep -q '"decision": *"block"' \
  || fail "cold repo: the Stop was ALLOWED after a freehand edit (RED: cold branch nudges + exit 0, arms no marker)"
printf '%s' "$out" | grep -qi 'setup' \
  || fail "the cold-engage block must offer 'sift setup' (got: $out)"

# ---- after `sift setup`: the COLD gate clears but the edit is NOT laundered ---------------
# Setup writes config, so stop-block (keying cold-engage staleness on config) clears the now
# stale cold-engage marker. But the original freehand edit is still unpacketed, so the handoff
# to FORT-1 keeps the Stop blocked — now offering `sift packet`, NOT `sift setup`. This proves
# an agent cannot launder a cold edit into a clean Stop by running setup. The cold-engage
# marker must be gone (handed off), and the block must no longer be the cold-setup prompt.
SIFT="$ROOT/bin/sift"
SIFT_REPO_ROOT="$T" CLAUDE_PROJECT_DIR="$T" bash "$SIFT" setup >/dev/null 2>&1 || true
[ -f "$T/sift-harness.config.json" ] || fail "scaffold: sift setup did not write config into the cold repo"
out2="$(printf '{}' | CLAUDE_PROJECT_DIR="$T" bash "$STOP" 2>/dev/null || true)"
[ ! -f "$T/.harness/cold-engage" ] || fail "after \`sift setup\` the stale cold-engage marker must be cleared"
printf '%s' "$out2" | grep -q '"decision": *"block"' \
  || fail "after \`sift setup\` an unpacketed cold edit must still block (handoff to FORT-1), not be laundered clean (got: $out2)"
printf '%s' "$out2" | grep -qi 'packet' \
  || fail "after setup the block must hand off to FORT-1 (offer 'sift packet'), got: $out2"

# ---- the throwaway escape: `sift focus --clear` releases the turn -------------------------
SIFT_REPO_ROOT="$T" CLAUDE_PROJECT_DIR="$T" bash "$SIFT" focus --clear >/dev/null 2>&1 || true
out3="$(printf '{}' | CLAUDE_PROJECT_DIR="$T" bash "$STOP" 2>/dev/null || true)"
printf '%s' "$out3" | grep -q '"decision": *"block"' \
  && fail "\`sift focus --clear\` must release the turn (got a block: $out3)"

echo "PASS: cold edit -> Stop blocks offering setup; setup hands off to FORT-1 (no laundering); focus --clear releases; un-edited cold repo ends freely"
