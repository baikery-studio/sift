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
. "$_AUDIT_DIR/config.sh"; . "$_AUDIT_DIR/log.sh"; . "$_AUDIT_DIR/state.sh"; . "$_AUDIT_DIR/sign.sh"
SIFT_LOG="${SIFT_LOG:-$(config_path log)}"
SIFT_REVIEWS="${SIFT_REVIEWS:-$(config_path reviews)}"

# _audit_sig_check <log> <id> <reviews> — SOTA-3 signed-attestation check, run AFTER the three
# witness checks pass. Resolves the verdict event the confirmed binds (we.verdict_event), reads
# its recorded signer_pubkey, and if signed verifies the detached <id>.sig over that event_hash
# (the canonical verdict bytes) with the recorded PUBLIC key. Echoes the attestation line; rc 1
# only when a SIGNED claim fails to verify (a tampered/missing .sig) — an UNSIGNED confirmed is
# tamper-evident only and returns 0 (keyless default). Asymmetric: needs only the public key.
_audit_sig_check() {
  local log="$1" id="$2" reviews="$3"
  # (verdict_event_hash, signer_pubkey) for the terminal the confirmed binds.
  local pair veh pub
  pair="$(python3 -c 'import json,sys
log,pid=sys.argv[1],sys.argv[2]; term=None; by={}
for ln in open(log):
    if not ln.strip(): continue
    try: e=json.loads(ln)
    except Exception: continue
    if e.get("event_hash"): by[e["event_hash"]]=e
    if e.get("kind")=="lane.transition" and e.get("packet_id")==pid and e.get("to") in ("confirmed","partially_confirmed"):
        term=e
veh=((term or {}).get("witness_evidence") or {}).get("verdict_event","")
ve=by.get(veh) or {}
pub=(ve.get("witness_evidence") or {}).get("signer_pubkey","") or ""
print(veh+"\t"+pub)' "$log" "$id" 2>/dev/null)"
  veh="${pair%%	*}"; pub="${pair#*	}"
  if [ -z "$pub" ]; then
    echo "  attestation   : tamper-evident only (unsigned)"; return 0
  fi
  local sig="$reviews/$id.sig"
  if sift_verify "$pub" "$veh" "$sig"; then
    echo "  attestation   : signed-attested (verdict signed by recorded key: $pub)"; return 0
  fi
  echo "  attestation   : SIGNATURE FAILED (recorded signer but .sig missing/invalid)" >&2; return 1
}

sift_audit() {
  case "${1:-}" in
    --bundle)     shift; sift_audit_bundle "$@"; return $? ;;
    --help|-h|"") echo "usage: sift audit <packet_id> | sift audit --bundle <file> — replay-verify a confirmed packet from the repo+log, or a portable bundle on a foreign machine"; [ -z "${1:-}" ] && return 1 || return 0 ;;
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
  local _abody; _abody="$(python3 "$_AUDIT_DIR/_audit.py" "$SIFT_LOG" "$id" "$SIFT_REVIEWS")" || { printf '%s\n' "$_abody"; return 1; }
  printf '%s\n' "$_abody"
  _audit_sig_check "$SIFT_LOG" "$id" "$SIFT_REVIEWS"   # signed-attested / tamper-evident; rc 1 on a bad signature
}

# sift audit --bundle <file> — replay-verify a portable bundle on a FOREIGN machine, with no
# .harness / no other repo state present. Extracts the bundle to a temp dir and routes through
# the EXACT same three checks as the in-place audit (chain verify -> project_state terminal ->
# artifact re-hash), then surfaces the bundle's feature_sha cross-repo provenance.
sift_audit_bundle() {
  local bundle="${1:-}"
  [ -n "$bundle" ] && [ -f "$bundle" ] || { echo "AUDIT FAIL: bundle not found: $bundle" >&2; return 1; }
  local td; td="$(mktemp -d)"
  if ! python3 "$_AUDIT_DIR/_export.py" extract "$bundle" "$td" 2>/dev/null; then
    echo "AUDIT FAIL: bundle is malformed (cannot extract / missing manifest or log)" >&2; rm -rf "$td"; return 1
  fi
  local blog="$td/log.jsonl" brev="$td/reviews"
  local pid fsha
  pid="$(python3 -c 'import json,sys
try: print((json.load(open(sys.argv[1])) or {}).get("packet_id",""))
except Exception: print("")' "$td/bundle.json" 2>/dev/null)"
  [ -n "$pid" ] || { echo "AUDIT FAIL: bundle manifest has no packet_id" >&2; rm -rf "$td"; return 1; }
  # feature_sha for the provenance check comes from the CHAIN-AUTHENTICATED terminal event in
  # the carried log (its event_hash covers witness_evidence, and _valid_witness ties it to the
  # verdict event), NOT from bundle.json — bundle.json is unsigned metadata an attacker could
  # rewrite to spoof a PRESENT provenance against the wrong commit.
  fsha="$(python3 -c 'import json,sys
log,pid=sys.argv[1],sys.argv[2]; fs=""
for ln in open(log):
    if not ln.strip(): continue
    try: ev=json.loads(ln)
    except Exception: continue
    if ev.get("kind")=="lane.transition" and ev.get("packet_id")==pid and ev.get("to") in ("confirmed","partially_confirmed"):
        fs=(ev.get("witness_evidence") or {}).get("feature_sha","") or ""
print(fs)' "$blog" "$pid" 2>/dev/null)"

  local rc=0 reason=""
  # check 1: the carried chain prefix re-derives clean.
  if ! SIFT_LOG="$blog" verify_log_chain >/dev/null 2>&1; then
    rc=1; reason="bundle log chain does not verify (tampered)"
  fi
  # check 2: the packet replays to a witness-bound terminal from the bundle alone.
  if [ "$rc" -eq 0 ]; then
    local st; st="$(SIFT_LOG="$blog" SIFT_REVIEWS="$brev" project_state "$pid")"
    case "$st" in
      confirmed|partially_confirmed) ;;
      *) rc=1; reason="replays as '$st', not a witness-bound terminal" ;;
    esac
  fi
  # check 3: the bound artifacts re-hash (self-sufficient _audit.py reruns chain + replay too).
  local body="" sigline=""
  if [ "$rc" -eq 0 ]; then
    body="$(python3 "$_AUDIT_DIR/_audit.py" "$blog" "$pid" "$brev" 2>&1)" || { rc=1; reason="$body"; }
  fi
  # check 4 (SOTA-3): signed-attestation. An unsigned bundle reports tamper-evident only (rc 0);
  # a signed verdict whose .sig fails/absent in the bundle fails closed.
  if [ "$rc" -eq 0 ]; then
    sigline="$(_audit_sig_check "$blog" "$pid" "$brev" 2>&1)" || { rc=1; reason="$sigline"; }
  fi

  # feature_sha CROSS-REPO PROVENANCE (advisory but never silent): resolve the bundle's
  # feature_sha against the repo audit runs in. PRESENT = the reviewed commit is here; NOT-FOUND
  # = the bundle vouches for a commit this repo does not contain (a stranger must see this, or a
  # bundle from repo A verifies next to unrelated repo B unflagged).
  local repo="${SIFT_REPO_ROOT:-$(pwd)}" prov
  if [ -z "$fsha" ] || [ "$fsha" = nogit ]; then
    prov="feature_sha: (none recorded in bundle)"
  elif ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    prov="feature_sha $fsha: NOT-FOUND (cannot resolve: no git in audit repo)"
  elif git -C "$repo" cat-file -e "${fsha}^{commit}" >/dev/null 2>&1; then
    prov="feature_sha $fsha: PRESENT (the reviewed commit is in this repo)"
  else
    prov="feature_sha $fsha: NOT-FOUND (the bundle vouches for a commit not in this repo)"
  fi

  rm -rf "$td"
  if [ "$rc" -ne 0 ]; then
    echo "AUDIT FAIL (bundle:$pid): $reason" >&2
    echo "  $prov" >&2
    return 1
  fi
  printf '%s\n' "$body"
  [ -n "$sigline" ] && printf '%s\n' "$sigline"
  echo "  $prov"
}
