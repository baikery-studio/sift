#!/usr/bin/env bash
# Acceptance for SOTA-2-SEMANTIC-DEFAULT (HARDENED).
#
# NAMED MISSING CAPABILITY (the primary RED, fails first on HEAD):
#   witness_w3.sh '_w3_host_mode' enters host mode ONLY on an explicit override
#   (SIFT_W3_REQUIRE_HOST_VERDICT=1 or the profile flag). It does NOT auto-detect the
#   EXPLICIT agent-host signal SIFT_AGENT_HOST=1 that hooks/sessionstart.sh is supposed to
#   set under a live agent host. So with SIFT_AGENT_HOST=1 and NO host verdict authored, a
#   `sift review` still passes KEYLESS today -> the default `confirmed` does not mean
#   "reviewed" under an agent host. That is the gap this packet's GREEN driver closes.
#
# This test keys off the EXPLICIT SIFT_AGENT_HOST=1 signal, NOT ambient CLAUDE_PROJECT_DIR:
# auto-detecting an ambient host dir would silently flip CI (which often exports
# CLAUDE_PROJECT_DIR) into requiring a host verdict. The regression-guard (step 2) locks
# that — ambient CLAUDE_PROJECT_DIR with NO SIFT_AGENT_HOST must STAY keyless.
#
# COMPOSES WITH ITS DEPS (GREEN-driver assertions, not the primary RED):
#   - W3-WRITE-VERB-1: the accepted host verdict is authored through the sanctioned
#     'sift w3-verdict <id> <staging>' verb (sift's own code does the .harness write); a
#     direct agent write to .harness/reviews stays scope-guard DENIED.
#   - W3-SEM-1: the accepted verdict must satisfy the rubric-VALUE check — an all-fail
#     rubric must NOT pass even under host mode (key-presence is not enough).
#
# PRESERVES: offline/CI (no SIFT_AGENT_HOST) stays keyless; explicit opt-out works; the
# trust core is untouched; zero egress (tests/test-no-egress.sh) stays green.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
W3="$ROOT/profiles/software/witness_w3.sh"
SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS SIFT_W3_REQUIRE_HOST_VERDICT SIFT_W3_HOST_VERDICT SIFT_AGENT_HOST CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT 2>/dev/null || true

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export SIFT_REVIEWS="$T/reviews"; mkdir -p "$SIFT_REVIEWS"
PK="$T/pkt.md"; printf -- '---\nid: s2\nprofile: software\n---\ngoal: demo\n' > "$PK"

# build a 13-key rubric whose every value is the token in $1 (e.g. pass | fail), under a
# top-level "verdict":"pass" — the W3-SEM-1 shape.
rubric(){ python3 -c 'import json,sys
tok=sys.argv[1]
print(json.dumps({"verdict":"pass","confidence":0.9,"reason":"r","reviewer":"host","rubric":{("R%d"%i):tok for i in range(1,14)}}))' "$1"; }

# ============================================================================
# 1. PRIMARY RED (named missing capability): EXPLICIT agent-host signal set
#    (SIFT_AGENT_HOST=1), NO host verdict authored -> W3 must FAIL (review-grade).
#    HEAD: _w3_host_mode does not read SIFT_AGENT_HOST, so this PASSES keyless -> RED.
#    This runs FIRST so the RED names auto-detection, not a missing verb / rubric check.
# ============================================================================
rm -f "$SIFT_REVIEWS/s2.w3.json"
out="$(env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT SIFT_AGENT_HOST=1 SIFT_REPO_ROOT="$ROOT" bash "$W3" "$PK" s2 2>/dev/null)"; rc=$?
[ $rc -ne 0 ] || fail "SIFT_AGENT_HOST=1 set but missing host verdict still PASSED W3 keyless (RED: host mode not auto-detected from the explicit SIFT_AGENT_HOST signal — _w3_host_mode must treat SIFT_AGENT_HOST=1 as agent-host-present unless SIFT_W3_HOST_VERDICT=off): $out"

# ============================================================================
# 2. REGRESSION-GUARD: ambient CLAUDE_PROJECT_DIR alone (NO SIFT_AGENT_HOST) must STAY
#    keyless. The host signal is the EXPLICIT SIFT_AGENT_HOST, never an ambient host dir
#    — otherwise CI (which exports CLAUDE_PROJECT_DIR) would silently require a host verdict.
#    Guards against an over-broad GREEN that keys off CLAUDE_PROJECT_DIR.
# ============================================================================
rm -f "$SIFT_REVIEWS/s2.w3.json"
out="$(env -u SIFT_AGENT_HOST CLAUDE_PROJECT_DIR="$T" SIFT_REPO_ROOT="$ROOT" bash "$W3" "$PK" s2 2>/dev/null)"; rc=$?
[ $rc -eq 0 ] || fail "ambient CLAUDE_PROJECT_DIR (no SIFT_AGENT_HOST) flipped into host mode (over-broad: CI would break) — the agent-host signal must be the EXPLICIT SIFT_AGENT_HOST=1: $out"

# ============================================================================
# 3. SANCTIONED AUTHORING (W3-WRITE-VERB-1): a direct agent write to .harness/reviews is
#    scope-guard DENIED, and the verdict is landed via 'sift w3-verdict <id> <staging>'.
#    With SIFT_AGENT_HOST=1 + that landed all-PASS verdict -> W3 PASSES; bytes preserved.
# ============================================================================
( . "$ROOT/kernel/scope_guard.sh"
  scope_guard_decision Write ".harness/reviews/s2.w3.json" >/dev/null 2>&1; rc=$?
  [ $rc -eq 2 ] || { echo "scope guard did NOT hard-deny a direct .harness/reviews write"; exit 1; }
) || fail "precondition: the scope guard must hard-deny a direct .harness write (that is why the verdict goes through 'sift w3-verdict')"

STAGE="$T/staging.w3.json"            # an in-scope path the agent is allowed to write
rubric pass > "$STAGE"
# step 2 above ran keyless W3, which persists its own s2.w3.json; clear that stale keyless
# artifact so the verb lands the host verdict fresh (under a real agent host keyless never
# runs, so there is nothing to clobber — w3-verdict's no-clobber guard is otherwise correct).
rm -f "$SIFT_REVIEWS/s2.w3.json"
env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT SIFT_REPO_ROOT="$ROOT" SIFT_REVIEWS="$SIFT_REVIEWS" \
  bash "$SIFT" w3-verdict s2 "$STAGE" >/dev/null 2>&1 \
  || fail "'sift w3-verdict' (W3-WRITE-VERB-1) failed to land a well-formed staged host verdict"
[ -f "$SIFT_REVIEWS/s2.w3.json" ] || fail "'sift w3-verdict' did not land the canonical .harness/reviews/s2.w3.json artifact"
LANDED="$(cat "$SIFT_REVIEWS/s2.w3.json")"
out="$(env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT SIFT_AGENT_HOST=1 SIFT_REPO_ROOT="$ROOT" bash "$W3" "$PK" s2 2>/dev/null)"; rc=$?
[ $rc -eq 0 ] || fail "SIFT_AGENT_HOST=1 + a sanctioned all-pass host verdict did not pass W3 ($out)"
[ "$(cat "$SIFT_REVIEWS/s2.w3.json")" = "$LANDED" ] || fail "W3 overwrote the host verdict bytes the verb landed"

# ============================================================================
# 4. COMPOSES WITH W3-SEM-1: an ALL-FAIL rubric (every R1-R13 reads "fail" under a
#    top-level "verdict":"pass") must NOT pass even under the agent host. Key-presence is
#    not enough — the accepted verdict must satisfy the rubric-VALUE check.
# ============================================================================
rubric fail > "$SIFT_REVIEWS/s2.w3.json"
out="$(env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT SIFT_AGENT_HOST=1 SIFT_REPO_ROOT="$ROOT" bash "$W3" "$PK" s2 2>/dev/null)"; rc=$?
[ $rc -ne 0 ] || fail "an all-fail rubric PASSED host-mode W3 under SIFT_AGENT_HOST (W3-SEM-1 rubric-VALUE check not composed — SOTA-2 must require a semantically-valid verdict, not mere key presence): $out"

# ============================================================================
# 5. OFFLINE / CI (no SIFT_AGENT_HOST, no override) -> keyless structural pass still ok
#    (default offline loop / selftest unchanged).
# ============================================================================
rm -f "$SIFT_REVIEWS/s2.w3.json"
out="$(env -u SIFT_AGENT_HOST -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT SIFT_REPO_ROOT="$ROOT" bash "$W3" "$PK" s2 2>/dev/null)"; rc=$?
[ $rc -eq 0 ] || fail "offline keyless W3 no longer passes a structural review (default broke): $out"

# ============================================================================
# 6. EXPLICIT OPT-OUT under an agent host -> keyless again (escape hatch).
# ============================================================================
out="$(env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT SIFT_AGENT_HOST=1 SIFT_W3_HOST_VERDICT=off SIFT_REPO_ROOT="$ROOT" bash "$W3" "$PK" s2 2>/dev/null)"; rc=$?
[ $rc -eq 0 ] || fail "SIFT_W3_HOST_VERDICT=off under SIFT_AGENT_HOST=1 did not fall back to keyless"

# ============================================================================
# 7. zero egress preserved.
# ============================================================================
bash "$ROOT/tests/test-no-egress.sh" >/dev/null 2>&1 || fail "test-no-egress.sh regressed"

echo "PASS: an explicit SIFT_AGENT_HOST=1 auto-requires a sanctioned, W3-SEM-1-valid host R1-R13 verdict (semantic default); ambient CLAUDE_PROJECT_DIR stays keyless; offline stays keyless; opt-out works; zero egress preserved"
