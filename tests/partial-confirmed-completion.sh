#!/usr/bin/env bash
# selftest: a partially_confirmed (soft-floor-capped) member counts as DONE for wave
# completion. RED before the fix: sift_next only skipped confirmed|superseded, so a
# soft-floored member was re-emitted as the resume target forever (wedging `sift drive`
# at its "unexpected state" arm), and sift_wave_review demanded strict `= confirmed`, so
# a wave with one soft-floored member could never ship. The trust core (audit/doctor/
# _state) already treats partially_confirmed as a witness-bound terminal; this proves the
# driver's completion logic agrees.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
( unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS
  cd "$W"; export SIFT_REPO_ROOT="$W"
  "$SIFT" setup >/dev/null 2>&1
  git init -q; git config user.email t@t; git config user.name t
  mkdir -p out tasks/waves

  # member A: declares a valid soft_floor (toy profile allows 'unverified_marker') -> caps to
  # partially_confirmed. member B: no soft_floor -> confirmed.
  for spec in "sfa:soft_floor: unverified_marker" "sfb:"; do
    id="${spec%%:*}"; sf="${spec#*:}"
    { printf -- '---\nid: %s\nprofile: toy\ngoal: produce a greeting artifact that carries the marker\n' "$id"
      [ -n "$sf" ] && printf '%s\n' "$sf"
      printf 'artifact:\n  path: out/%s.txt\n  marker: HELLO-SIFT\n---\n' "$id"
    } > "tasks/packets/$id.md"
    printf 'a greeting\nHELLO-SIFT\n' > "out/$id.txt"
  done
  git add -A; git commit -qm x

  for id in sfa sfb; do
    "$SIFT" plan "$id"    >/dev/null 2>&1
    "$SIFT" execute "$id" >/dev/null 2>&1
    "$SIFT" review "$id"  >/dev/null 2>&1 || true
  done

  [ "$("$SIFT" state sfa)" = partially_confirmed ] || fail "setup: sfa not partially_confirmed (got $("$SIFT" state sfa))"
  [ "$("$SIFT" state sfb)" = confirmed ]           || fail "setup: sfb not confirmed (got $("$SIFT" state sfb))"

  printf '{"id":"wv","members":["sfa","sfb"]}\n' > tasks/waves/wv.json

  # 1. sift_next must report the wave done, not re-emit the partially_confirmed member.
  nxt="$("$SIFT" next wv 2>/dev/null || true)"
  [ "$nxt" = "ALL-CONFIRMED" ] || fail "sift next re-emitted '$nxt' for a partially_confirmed member (RED: not treated as done)"

  # 2. wave-review's gate_ready must accept partially_confirmed (it may later fail on wiring,
  #    but it must get PAST the completion gate, not reject the soft-floored member).
  wr="$("$SIFT" wave-review wv 2>&1 || true)"
  printf '%s' "$wr" | grep -q 'not gate_ready' && fail "wave-review rejected a partially_confirmed member at gate_ready (RED)"
  true
)
echo "PASS: a soft-floor-capped partially_confirmed member counts as done for sift next + wave-review gate_ready"
