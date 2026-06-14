#!/usr/bin/env bash
# kernel/sign.sh — OPT-IN detached SSH signing of the verdict event_hash (SOTA-3-SIGN-VERDICT).
# Makes a confirmed cryptographically ATTESTABLE (not just tamper-evident): a keyholder
# (operator/CI), distinct from the worker-agent that produced the diff, signs the canonical
# verdict bytes (the chained review.verdict event_hash) with a LOCAL key via `ssh-keygen -Y`.
# ZERO NETWORK: a local key + ssh-keygen is not egress (test-no-egress stays green). The signer
# PUBLIC key is recorded inside the verdict event so the chain hash covers signer identity; the
# auditor verifies asymmetrically with that public key and cannot forge. Keyless stays default.
_SIGN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
_SIFT_SIGN_NS="sift"            # ssh signature namespace
_SIFT_SIGN_PRINCIPAL="sift"     # allowed_signers principal / verify identity

# sift_sign_available <keyfile> -> rc 0 if ssh-keygen + a usable private+public keypair exist.
sift_sign_available() {
  local key="$1"
  command -v ssh-keygen >/dev/null 2>&1 || return 1
  [ -n "$key" ] && [ -f "$key" ] && [ -f "$key.pub" ] || return 1
  return 0
}

# sift_sign_pubkey <keyfile> -> echo the recorded signer identity: the 2-field public key
# "<keytype> <keydata>" (no comment), which is also exactly an allowed_signers key field.
sift_sign_pubkey() {
  awk '{print $1" "$2; exit}' "$1.pub" 2>/dev/null
}

# sift_sign <keyfile> <message> <out_sig> -> sign the message bytes with `ssh-keygen -Y sign`,
# writing a detached signature to <out_sig>. rc 0 on success.
sift_sign() {
  local key="$1" msg="$2" out="$3"
  sift_sign_available "$key" || return 1
  local td; td="$(mktemp -d)" || return 1
  printf '%s' "$msg" > "$td/m"
  if ssh-keygen -Y sign -f "$key" -n "$_SIFT_SIGN_NS" "$td/m" >/dev/null 2>&1 && [ -f "$td/m.sig" ]; then
    # land atomically: copy to a temp ON THE SAME FILESYSTEM as $out, then rename (a bare
    # cross-filesystem `mv` from /tmp is copy+delete, non-atomic — a crash could leave a partial
    # .sig). os.replace-style rename within the reviews dir is atomic.
    local _to="$out.tmp.$$"
    if cp "$td/m.sig" "$_to" 2>/dev/null && mv "$_to" "$out" 2>/dev/null; then
      rm -rf "$td"; return 0
    fi
    rm -f "$_to" 2>/dev/null || true; rm -rf "$td"; return 1
  fi
  rm -rf "$td"; return 1
}

# sift_verify <pubkey "type data"> <message> <sigfile> -> verify the detached signature over the
# message bytes against the recorded public key with `ssh-keygen -Y verify`. rc 0 only on a
# valid signature. Builds a throwaway allowed_signers from the recorded pubkey (asymmetric: the
# auditor needs only the public key, never the private one).
sift_verify() {
  local pub="$1" msg="$2" sig="$3"
  command -v ssh-keygen >/dev/null 2>&1 || return 1
  [ -n "$pub" ] && [ -s "$sig" ] || return 1
  local td; td="$(mktemp -d)" || return 1
  printf '%s' "$msg" > "$td/m"
  printf '%s %s\n' "$_SIFT_SIGN_PRINCIPAL" "$pub" > "$td/allowed"
  if ssh-keygen -Y verify -f "$td/allowed" -I "$_SIFT_SIGN_PRINCIPAL" -n "$_SIFT_SIGN_NS" -s "$sig" < "$td/m" >/dev/null 2>&1; then
    rm -rf "$td"; return 0
  fi
  rm -rf "$td"; return 1
}
