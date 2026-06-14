#!/usr/bin/env bash
# kernel/audit.sh — sift audit <id>: second-party replay-verification of a confirmed
# packet from the repo + log alone. Three independent checks, then a structured report:
#   1. the hash-chain verifies (tamper-evidence)
#   2. the packet replays to `confirmed` (project_state enforces the witness binding:
#      a witnessless/forged confirmed replays as `corrupt`)
#   3. each bound W2/W3/W4 artifact re-hashes to the value in the confirmed event
# Exit 0 = PASS, non-zero = FAIL with the exact reason. This is the moat: a party who
# did not build the work can verify the claim, needing nothing but the repository.
_AUDIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_AUDIT_DIR/config.sh"; . "$_AUDIT_DIR/log.sh"; . "$_AUDIT_DIR/state.sh"
SIFT_LOG="${SIFT_LOG:-$(config_path log)}"
SIFT_REVIEWS="${SIFT_REVIEWS:-$(config_path reviews)}"

sift_audit() {
  case "${1:-}" in
    --help|-h|"") echo "usage: sift audit <packet_id> — replay-verify a confirmed packet from the repo + log"; [ -z "${1:-}" ] && return 1 || return 0 ;;
  esac
  local id="$1"
  if ! verify_log_chain >/dev/null 2>&1; then
    echo "AUDIT FAIL ($id): log chain does not verify (tampered or schema-too-old — see verify-log)" >&2; return 1
  fi
  # A witness-bound terminal is {confirmed, partially_confirmed}: project_state binds both
  # with the same witness rigour (a soft-floored partially_confirmed still ran a real W3
  # verdict), so both are auditable. _audit.py names the grade in its report.
  local st; st="$(project_state "$id")"
  case "$st" in
    confirmed|partially_confirmed) ;;
    *) echo "AUDIT FAIL ($id): replays as '$st', not a witness-bound terminal" >&2; return 1 ;;
  esac
  python3 "$_AUDIT_DIR/_audit.py" "$SIFT_LOG" "$id" "$SIFT_REVIEWS"
}
