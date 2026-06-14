#!/usr/bin/env bash
# Acceptance for SOTA-3-SIGN-VERDICT. RED on HEAD: there is NO opt-in '--sign' path on
# 'sift review' and 'sift audit' has NO signature-verify. This drives sift END-TO-END
# (a keyless toy packet plan->execute->review->confirmed, CI-safe, no LLM) and proves the
# MISSING capability behaviorally:
#
#   GREEN (the capability this RED targets, absent on HEAD):
#     - 'sift review --sign' (key via SIFT_SIGN_KEY, default ~/.ssh/id_ed25519) signs the
#       canonical verdict event_hash with 'ssh-keygen -Y sign' (LOCAL key, ZERO network)
#       and writes a detached signature .harness/reviews/<id>.sig.
#     - the signer PUBLIC key is recorded INSIDE the chained review.verdict event's
#       witness_evidence (a 'signer'/'signer_pubkey' field), so the event_hash COVERS the
#       signer identity (tamper-evident for free — no new REQUIRED_WE field needed).
#     - 'sift audit' verifies the .sig against the recorded pubkey with 'ssh-keygen -Y
#       verify' and reports "signed-attested"; a tampered signature FAILS audit.
#     - '--sign' with no usable key FAILS closed (never a silent unsigned confirmed).
#
#   GREEN-GUARDS (invariants that must KEEP holding — co-assertions, not the RED):
#     - keyless DEFAULT unchanged: an UNSIGNED witness-bound confirmed still audits PASS.
#     - zero egress: the sign/verify path adds no network (test-no-egress.sh stays green).
#
# On HEAD: 'sift review --sign' ignores the flag (no .sig, no signer in the verdict event),
# and 'sift audit' never prints "signed-attested" — so the primary assertions FAIL (RED).
# The keyless-default and zero-egress guards already hold and must not be the thing that
# fails; structural guards pin that the RED is the MISSING --sign/verify capability, not a
# scaffold/host breakage.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
SIFT="$ROOT/bin/sift"
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS SIFT_REPO_ROOT SIFT_SIGN SIFT_SIGN_KEY 2>/dev/null || true

# ---- PRIMITIVE SANITY: ssh-keygen detached sign/verify round-trips offline. ------------
# The chosen attestation primitive must exist and work with NO network (a local key is not
# egress). If this host lacks it, that is a scaffold gap, reported distinctly from the RED.
command -v ssh-keygen >/dev/null 2>&1 || fail "scaffold: ssh-keygen required for signed attestation"
command -v git        >/dev/null 2>&1 || fail "scaffold: git required to drive the pipeline"
K="$(mktemp -d)"; trap 'rm -rf "$K"' EXIT
ssh-keygen -t ed25519 -N "" -C sift@sota3 -f "$K/id" >/dev/null 2>&1 || fail "scaffold: ephemeral key gen failed"
printf 'attest-these-bytes\n' > "$K/msg"
ssh-keygen -Y sign -f "$K/id" -n sift "$K/msg" >/dev/null 2>&1 || fail "scaffold: 'ssh-keygen -Y sign' failed (must work offline)"
# allowed_signers line is "<principal> <keytype> <keydata>" (2-field pubkey, no comment).
printf '%s %s\n' "sift@sota3" "$(awk '{print $1" "$2}' "$K/id.pub")" > "$K/allowed"
ssh-keygen -Y verify -f "$K/allowed" -I sift@sota3 -n sift -s "$K/msg.sig" < "$K/msg" >/dev/null 2>&1 \
  || fail "scaffold: valid detached signature did not verify with the public key"
printf 'tampered\n' > "$K/msg"
if ssh-keygen -Y verify -f "$K/allowed" -I sift@sota3 -n sift -s "$K/msg.sig" < "$K/msg" >/dev/null 2>&1; then
  fail "scaffold: tampered bytes still verified — primitive is not binding"
fi

# Author the SAME keyless toy packet the harness confirms end-to-end (CI-safe, no LLM).
_author_repo(){ # <repo_dir>
  local W="$1"
  cd "$W" || fail "scaffold: cannot cd to $W"
  export SIFT_REPO_ROOT="$W"
  git init -q . && git config user.email t@t && git config user.name t || fail "scaffold: git init failed"
  bash "$SIFT" setup >/dev/null 2>&1 || fail "scaffold: 'sift setup' failed"
  mkdir -p out
  cat > tasks/packets/sigprobe.md <<'EOF'
---
id: sigprobe
profile: toy
goal: produce a greeting artifact carrying the marker
artifact:
  path: out/e.txt
  marker: SG-OK
---
EOF
  printf 'a greeting produced end to end\nSG-OK\n' > out/e.txt
  git add -A && git commit -qm base >/dev/null 2>&1 || fail "scaffold: baseline commit failed"
}

# =========================================================================================
# 0. CONTROL (keyless default, GREEN-GUARD): an UNSIGNED confirmed drives clean and audits
#    PASS. Proves the host/drive works (so a later RED is the capability, not a breakage)
#    AND pins the keyless-default-unchanged invariant.
# =========================================================================================
WC="$(mktemp -d)"; _author_repo "$WC"
bash "$SIFT" plan    sigprobe >/dev/null 2>&1 || fail "scaffold: 'sift plan' failed (control)"
bash "$SIFT" execute sigprobe >/dev/null 2>&1 || fail "scaffold: 'sift execute' failed (control)"
bash "$SIFT" review  sigprobe >/dev/null 2>&1 || fail "scaffold: 'sift review' (keyless) failed (control)"
[ "$(bash "$SIFT" state sigprobe 2>/dev/null)" = confirmed ] \
  || fail "scaffold: keyless control packet did not reach 'confirmed' — drive is broken, not the defect"
bash "$SIFT" audit sigprobe >/dev/null 2>&1 \
  || fail "GREEN-GUARD broken: an UNSIGNED witness-bound confirmed must still audit PASS (keyless default unchanged)"
# the keyless confirmed must NOT carry a detached signature.
[ -e "$WC/.harness/reviews/sigprobe.sig" ] \
  && fail "scaffold: keyless control wrote a .sig (default must stay unsigned)"
rm -rf "$WC"

# =========================================================================================
# 1. PRIMARY RED — the MISSING opt-in '--sign' signed-attestation surface, end-to-end.
#    Drive review WITH --sign and a LOCAL ephemeral key (SIFT_SIGN_KEY). The GREEN target
#    must: (a) write a detached .harness/reviews/<id>.sig, (b) record the signer PUBLIC key
#    inside the chained review.verdict event's witness_evidence, and (c) make 'sift audit'
#    report "signed-attested". None of these exist on HEAD -> RED.
# =========================================================================================
WS="$(mktemp -d)"; _author_repo "$WS"
ssh-keygen -t ed25519 -N "" -C sift@signer -f "$WS/signer" >/dev/null 2>&1 || fail "scaffold: signer key gen failed"
export SIFT_SIGN_KEY="$WS/signer"
SIGNER_PUB="$(awk '{print $2}' "$WS/signer.pub")"   # the base64 key body, recorded as signer identity

bash "$SIFT" plan    sigprobe >/dev/null 2>&1 || fail "scaffold: 'sift plan' failed (sign run)"
bash "$SIFT" execute sigprobe >/dev/null 2>&1 || fail "scaffold: 'sift execute' failed (sign run)"
# 'sift review --sign' is the opt-in path. On HEAD the flag is ignored (review still runs
# keyless); the GREEN target signs the verdict event_hash with the local key.
bash "$SIFT" review  sigprobe --sign >/dev/null 2>&1 || true
st="$(bash "$SIFT" state sigprobe 2>/dev/null)"
[ "$st" = confirmed ] \
  || fail "scaffold: 'sift review --sign' did not reach 'confirmed' (state=$st) — signing must not break the confirm, it must ADD a signature"

# (a) a detached signature artifact must exist. RED today: --sign is a no-op, no .sig.
[ -s "$WS/.harness/reviews/sigprobe.sig" ] \
  || fail "no detached signature written by 'sift review --sign' (RED: no opt-in --sign signing path — must write .harness/reviews/<id>.sig with 'ssh-keygen -Y sign')"

# (b) the signer PUBLIC key must be recorded INSIDE the chained review.verdict event's
#     witness_evidence, so the event_hash covers signer identity. RED today: the verdict
#     event carries no signer field (pipeline.sh:148 vj JSON has no signer/signer_pubkey).
#     Accept ANY witness_evidence field carrying the pubkey (signer/signer_pubkey/...).
_sig_chk(){ python3 "$1" "$2" "$3"; }   # <pyfile> <log> <pubkey> -> prints yes|no
cat > "$K/sigchk.py" <<'PY'
import json, sys
log, pub = sys.argv[1], sys.argv[2]
found = False
for ln in open(log):
    try:
        e = json.loads(ln)
    except Exception:
        continue
    if e.get("kind") == "review.verdict" and e.get("packet_id") == "sigprobe":
        if pub in json.dumps(e.get("witness_evidence", {})):
            found = True
print("yes" if found else "no")
PY
HAS_SIGNER="$(_sig_chk "$K/sigchk.py" "$WS/.harness/log.jsonl" "$SIGNER_PUB")"
[ "$HAS_SIGNER" = yes ] \
  || fail "signer public key NOT recorded in the chained review.verdict witness_evidence (RED: the verdict event must embed the signer pubkey so its event_hash covers signer identity — pipeline.sh vj JSON has no signer field)"

# (c) 'sift audit' must verify the signature and report "signed-attested". RED today:
#     kernel/audit.sh + _audit.py have no 'ssh-keygen -Y verify' / signed-attested path.
adout="$(bash "$SIFT" audit sigprobe 2>&1)"
bash "$SIFT" audit sigprobe >/dev/null 2>&1 \
  || fail "scaffold: 'sift audit' rejected a genuine signed confirmed before reaching the signature check: $adout"
printf '%s' "$adout" | grep -qi 'signed-attested' \
  || fail "audit did not report 'signed-attested' for a --sign confirmed (RED: 'sift audit' has no signature-verify path — must 'ssh-keygen -Y verify' the .sig against the recorded pubkey). audit said: $adout"

# =========================================================================================
# 2. TAMPER — a signed confirmed whose detached signature is corrupted MUST fail audit
#    verify. (The audit-grade property: the signature is binding.) RED today: audit never
#    looks at the .sig, so corruption is invisible and audit still PASSES.
# =========================================================================================
printf 'corrupt-signature-bytes\n' > "$WS/.harness/reviews/sigprobe.sig"
if bash "$SIFT" audit sigprobe >/dev/null 2>&1; then
  fail "'sift audit' PASSED a signed confirmed with a CORRUPTED signature (RED: no signature-verify — a tampered .sig must fail verify)"
fi
rm -rf "$WS"

# =========================================================================================
# 3. FAIL-CLOSED — '--sign' requested but the key is unavailable MUST fail the review;
#    never silently emit an unsigned confirmed when signing was required. RED today: --sign
#    is ignored, so review confirms keyless (does not fail closed).
# =========================================================================================
WF="$(mktemp -d)"; _author_repo "$WF"
export SIFT_SIGN_KEY="$WF/does-not-exist-key"   # no such key -> signing must fail closed
bash "$SIFT" plan    sigprobe >/dev/null 2>&1 || fail "scaffold: 'sift plan' failed (fail-closed run)"
bash "$SIFT" execute sigprobe >/dev/null 2>&1 || fail "scaffold: 'sift execute' failed (fail-closed run)"
bash "$SIFT" review  sigprobe --sign >/dev/null 2>&1 || true
stf="$(bash "$SIFT" state sigprobe 2>/dev/null)"
if [ "$stf" = confirmed ]; then
  fail "'sift review --sign' with a MISSING key reached 'confirmed' (RED: --sign must FAIL CLOSED, never emit a silent unsigned confirmed when signing was required)"
fi
# and no .sig was forged.
[ -e "$WF/.harness/reviews/sigprobe.sig" ] \
  && fail "scaffold: fail-closed run wrote a .sig despite the missing key"
unset SIFT_SIGN_KEY
rm -rf "$WF"

# =========================================================================================
# 4. ZERO EGRESS (GREEN-GUARD): the sign/verify path adds no network.
# =========================================================================================
bash "$ROOT/tests/test-no-egress.sh" >/dev/null 2>&1 \
  || fail "GREEN-GUARD broken: test-no-egress.sh regressed (signing/verify must be local-only, zero network)"

# ---- STRUCTURAL GUARDS: pin that the behavioral pass rests on the REAL --sign/verify wiring.
# We only reach here when every behavioral assertion above passed (each `fail`s + exits on
# failure). On HEAD (RED) those exit first, so these guards are never reached. In GREEN they
# confirm the capability is genuinely wired (a --sign path in the spine, a signature-verify in
# audit) rather than the behavior passing for some unrelated reason.
grep -qE '\-\-sign|SIFT_SIGN|sift_sign' "$ROOT/kernel/pipeline.sh" 2>/dev/null \
  || fail "signed-attestation behavior passed but no --sign/SIFT_SIGN path is wired in pipeline.sh — investigate"
grep -qiE 'ssh-keygen[^\n]*-Y[[:space:]]+verify|signed-attested|sift_verify' "$ROOT/kernel/audit.sh" "$ROOT/kernel/sign.sh" 2>/dev/null \
  || fail "signed-attestation behavior passed but no signature-verify path is wired in audit — investigate"

echo "PASS: opt-in 'sift review --sign' signs the verdict event_hash with a local key, records the signer pubkey in the chained verdict event, 'sift audit' reports signed-attested and fails a tampered signature; --sign fails closed without a key; keyless default + zero egress preserved"
