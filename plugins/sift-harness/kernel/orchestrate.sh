#!/usr/bin/env bash
# kernel/orchestrate.sh — the orchestrator decision-trace surface (ORCH-4). A second party
# reconstructs not just WHAT was built (the witness-bound confirmeds, via `sift audit`) but WHY
# each step was chosen (the orchestrator's decisions, via `sift trace`), and that record rides
# the SAME tamper-evident hash chain WITHOUT ever being able to move a packet's state.
#
# Above-core boundary (load-bearing, EMERGENT — never add orch.* to a kind-allowlist):
# kernel/_state.py replay consumes ONLY kind=='lane.transition' and binds ONLY
# kind=='review.verdict'; kernel/_log.py takes `kind` straight from SIFT_KIND with no allowlist.
# So an orch.* event is hash-chained + tamper-checked + replay-verifiable, yet INERT to state
# projection. This file is the sanctioned way to use that: an emit helper and a read-only reader.
_ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_ORCH_DIR/config.sh"; . "$_ORCH_DIR/log.sh"
SIFT_LOG="${SIFT_LOG:-$(config_path log)}"

# Wave-level events have no member packet, so they ride a RESERVED scope id `__wave__:<wid>`
# (_log.py reads SIFT_PACKET; a wave event needs an id). orch.* / packet.emit / coverage.gap are
# free-form kinds the core treats as inert — replay never consumes them.
_orch_wscope() { printf '__wave__:%s' "$1"; }

# sift_orch_log <wid> <kind> <json-reason> — the ONLY sanctioned orchestrator emit. The driver
# never hand-rolls log_append. Records actor=orchestrator on the reserved wave scope.
sift_orch_log() {
  local wid="${1:-}" kind="${2:-}" reason="${3:-}"
  # default the reason to {} WITHOUT a `${3:-{}}` brace-expansion (bash parses its first `}` as
  # the closer, appending a literal `}` and corrupting a real JSON payload to `{...}}`).
  [ -n "$reason" ] || reason='{}'
  [ -n "$wid" ] && [ -n "$kind" ] || { echo "[sift] usage: sift_orch_log <wave-id> <kind> <json-reason>" >&2; return 2; }
  case "$kind" in
    orch.*|packet.emit|coverage.gap) ;;
    *) echo "[sift] orchestrate: refusing to emit non-orchestrator kind '$kind' (use orch.*/packet.emit/coverage.gap)" >&2; return 2 ;;
  esac
  SIFT_ACTOR=orchestrator log_append "$kind" _ _ "$(_orch_wscope "$wid")" "$reason" >/dev/null
}

# sift_trace <wid> — read-only: surface a wave's orchestrator decision trace from the VERIFIED
# log, in chain order. Shows the wave-scoped orch.* / packet.emit / coverage.gap events for
# THIS wave only (filtered by the reserved `__wave__:<wid>` scope), so it cannot leak another
# wave's decisions. `sift audit` answers WHAT; `sift trace` answers WHY.
sift_trace() {
  case "${1:-}" in
    --help|-h|"") echo "usage: sift trace <wave-id> — print a wave's orchestrator decision trace (orch.* / packet.emit) from the verified log"; [ -z "${1:-}" ] && return 1 || return 0 ;;
  esac
  local wid="$1"
  [ -f "$SIFT_LOG" ] || { echo "[sift] trace $wid: no log at $SIFT_LOG" >&2; return 1; }
  if ! verify_log_chain >/dev/null 2>&1; then
    echo "[sift] trace $wid: WARNING — log chain does not verify; trace is from a tampered log (run \`sift verify-log\`)" >&2
  fi
  SIFT_TRACE_WID="$wid" python3 -c '
import json, os, sys
log = sys.argv[1]; scope = "__wave__:" + os.environ["SIFT_TRACE_WID"]
rows = []
for ln in open(log):
    if not ln.strip(): continue
    try: e = json.loads(ln)
    except Exception: continue
    if e.get("packet_id") != scope: continue
    k = e.get("kind", "")
    if not (k.startswith("orch.") or k in ("packet.emit", "coverage.gap")): continue
    rows.append(e)
if not rows:
    print("[trace %s] no orchestrator decisions recorded for this wave" % os.environ["SIFT_TRACE_WID"]); sys.exit(0)
print("[trace %s] %d orchestrator decision(s):" % (os.environ["SIFT_TRACE_WID"], len(rows)))
for e in rows:
    we = e.get("witness_evidence")
    detail = json.dumps(we) if we not in (None, "", {}) else ""
    print("  seq %-4s %-16s %s" % (e.get("seq"), e.get("kind"), detail))
' "$SIFT_LOG"
}
