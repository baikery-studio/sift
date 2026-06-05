#!/usr/bin/env bash
# Acceptance for PRV-3-HOST-CONTRACT. Simulates a Stop-honoring host + a scripted compliant
# agent and asserts the turn cannot end until the work is confirmed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -q 'host-contract' "$ROOT/docs/INSTALL_VERIFICATION.md" || fail "INSTALL_VERIFICATION has no host-contract record (RED)"

w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
export SIFT_REPO_ROOT="$w"; "$SIFT" setup >/dev/null 2>&1
stop(){ printf '{}' | SIFT_REPO_ROOT="$w" bash "$ROOT/hooks/stop-block.sh" 2>/dev/null || true; }
blocks(){ printf '%s' "$1" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; }

# the lazy agent does a freehand Bash write (arms the engage-gate)
printf '{"tool_name":"Bash","tool_input":{"command":"echo impl > %s/out/feat.txt"}}' "$w" \
  | SIFT_REPO_ROOT="$w" bash "$ROOT/hooks/posttool-reset.sh" >/dev/null 2>&1 || true

# CONTROL: the premature end IS refused (a non-honoring host would have ended here)
blocks "$(stop)" || fail "host-contract control: premature end was NOT refused"

# the Stop-honoring host loop: refuse -> scripted agent remediates one step -> retry
state=0; steps=0; ended=0
while [ "$steps" -lt 8 ]; do
  steps=$((steps+1)); out="$(stop)"
  if blocks "$out"; then
    case "$state" in
      0) "$SIFT" packet new feat --profile toy >/dev/null 2>&1
         mkdir -p "$w/out"; printf 'a scaffolded greeting\nfeat-OK\n' > "$w/out/feat.txt"
         "$SIFT" plan feat >/dev/null 2>&1 ;;
      1) "$SIFT" execute feat >/dev/null 2>&1 ;;
      2) "$SIFT" review  feat >/dev/null 2>&1 ;;
      *) fail "still blocked after the full remediation sequence" ;;
    esac
    state=$((state+1))
  else
    ended=1; break
  fi
done
[ "$ended" = 1 ] || fail "host could never end the turn (loop did not converge)"
[ "$("$SIFT" state feat 2>/dev/null)" = confirmed ] || fail "turn ended but packet is not confirmed"
[ "$state" -ge 3 ] || fail "turn ended before the agent was actually forced through the loop"
echo "PASS: a Stop-honoring host refuses the premature end and releases only after confirmed (refuse->remediate->release verified)"
