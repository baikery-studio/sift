#!/usr/bin/env bash
# kernel/drive.sh — `sift drive <wave>`: a deterministic drive loop ABOVE the trust core.
# Reads the log-derived cursor (sift_next), dispatches the EXISTING pipeline step by
# project_state under the dispatch lock held for the WHOLE plan->execute->review iteration
# (closing the WIP=1 gap where the lock covered only execute), and repeats until
# sift_next==ALL-CONFIRMED, then runs the wave-review. DONE IS DERIVED from the log, never a
# flag the loop sets. The loop NEVER emits lane.transition/review.verdict itself — only the
# pipeline's real witnesses may move state — and records its dispatch CHOICES as orch.decision
# (ORCH-4's surface), which are chained + auditable but INERT to state projection.
_DRIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_DRIVE_DIR/config.sh"; . "$_DRIVE_DIR/state.sh"; . "$_DRIVE_DIR/lock.sh"
. "$_DRIVE_DIR/next.sh"; . "$_DRIVE_DIR/wave.sh"; . "$_DRIVE_DIR/orchestrate.sh"
. "$_DRIVE_DIR/pipeline.sh"
SIFT_STATE="${SIFT_STATE:-$(config_path state)}"

sift_drive() {
  case "${1:-}" in
    --help|-h|"") echo "usage: sift drive <wave-id> — drive the wave to ALL-CONFIRMED then wave-review (done is derived from the log, never asserted)"; [ -z "${1:-}" ] && return 1 || return 0 ;;
  esac
  local wid="$1"
  # If killed mid-iteration (while holding the dispatch lock), release it so the next run is not
  # wedged. (lock.sh's PID-liveness reclaim would also recover it, but this is immediate.)
  trap 'SIFT_DRIVE_OWNS_LOCK=; sift_lock_release 2>/dev/null || true; trap - INT TERM; return 130' INT TERM
  # No-progress guard so the loop NEVER spins: if the same (packet,state) recurs across ticks
  # (e.g. a packet whose acceptance keeps failing), halt after a retry ceiling. Done is still
  # derived (sift_next==ALL-CONFIRMED); this only bounds a non-advancing wave.
  local retry_ceiling=4 stall=0 last_key="" ticks=0 max_ticks=100000
  while :; do
    ticks=$((ticks + 1))
    [ "$ticks" -le "$max_ticks" ] || { echo "[sift] drive $wid: tick ceiling reached — stopping (no infinite spin)" >&2; return 1; }

    local id rc
    id="$(sift_next "$wid")"; rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "[sift] drive $wid: cursor unavailable (sift_next rc=$rc) — stopping, not spinning" >&2; return "$rc"
    fi
    if [ "$id" = ALL-CONFIRMED ]; then
      sift_orch_log "$wid" orch.decision '{"action":"complete","reason":"ALL-CONFIRMED"}' 2>/dev/null || true
      sift_wave_review "$wid"; return $?
    fi

    local st; st="$(project_state "$id")"
    local key="$id:$st"
    if [ "$key" = "$last_key" ]; then stall=$((stall + 1)); else stall=0; last_key="$key"; fi
    if [ "$stall" -ge "$retry_ceiling" ]; then
      sift_orch_log "$wid" orch.decision "$(printf '{"action":"halt","reason":"retry_ceiling","packet":"%s","state":"%s"}' "$id" "$st")" 2>/dev/null || true
      echo "[sift] drive $wid: no progress on '$id' (state '$st') after $retry_ceiling attempts — halting" >&2; return 1
    fi

    # WIP=1 across the iteration: hold the dispatch lock for the whole plan/execute/review, not
    # just execute. SIFT_DRIVE_OWNS_LOCK tells sift_execute not to re-acquire/release it.
    sift_lock_acquire "$id" || { echo "[sift] drive $wid: dispatch locked (WIP=1) — another process owns dispatch" >&2; return 1; }
    # NOT exported: sift_execute is a sourced function in THIS process and sees the shell var, but
    # child scripts (acceptance/witness subprocesses) must NOT inherit it — an exported flag could
    # let a child's sift_execute skip the lock (a WIP=1 bypass). Cleared after each iteration.
    SIFT_DRIVE_OWNS_LOCK=1

    local step
    case "$st" in
      submitted)                                step=plan ;;
      packeted|failed|review_failed)            step=execute ;;
      acceptance_met)                           step=review ;;
      reviewing)                                step=abort ;;   # crash-stuck: no live owner -> recover
      *)                                        step=stop ;;    # confirmed/superseded/corrupt/unknown: sift_next would have skipped/erred
    esac
    # record the dispatch CHOICE (inert orch.* event); the loop never emits a state transition.
    sift_orch_log "$wid" orch.decision "$(printf '{"action":"dispatch","step":"%s","packet":"%s","state":"%s"}' "$step" "$id" "$st")" 2>/dev/null || true
    case "$step" in
      plan)    sift_plan "$id"    >/dev/null 2>&1 || true ;;
      execute) sift_execute "$id" >/dev/null 2>&1 || true ;;
      review)  sift_review "$id"  >/dev/null 2>&1 || true ;;
      abort)   sift_abort "$id"   >/dev/null 2>&1 || true ;;
      stop)    unset SIFT_DRIVE_OWNS_LOCK; sift_lock_release
               echo "[sift] drive $wid: '$id' in unexpected state '$st' — stopping" >&2; return 1 ;;
    esac

    unset SIFT_DRIVE_OWNS_LOCK
    sift_lock_release
  done
}
