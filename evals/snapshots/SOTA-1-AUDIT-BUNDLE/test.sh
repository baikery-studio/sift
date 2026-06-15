#!/usr/bin/env bash
# Acceptance for SOTA-1-AUDIT-BUNDLE. RED on HEAD (no 'sift export', no 'audit --bundle').
# Proves the moat's transport: 'sift export' writes ONE portable bundle that 'sift audit
# --bundle' replay-verifies on a machine with NO .harness present, routing through audit.sh's
# exact 3-check order (chain -> project_state -> artifact re-hash). HARDENED:
#   - the bundle must CARRY and verify a partially_confirmed (dep TRUST-AUDIT-1 makes the
#     soft-floored terminal auditable), not only a confirmed;
#   - tamper is IN-CONTENT, two ways, each must make 'audit --bundle' FAIL:
#       (1) flip a byte of a LOG LINE inside the bundle  -> chain check must catch it;
#       (2) swap an ARTIFACT's (.w3.json) bytes inside the bundle -> re-hash must catch it.
#     (A trailing-byte append to a tar is ignored, so it is NOT a real tamper and is not used.)
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS 2>/dev/null || true

# 1. the verbs must exist (the named missing capability). Match a REAL 'export' dispatch
#    arm or its kernel files — NOT the bash 'export' keyword (lines 8-9 of bin/sift), which
#    would false-positive and mask the RED.
grep -qE '^[[:space:]]*export\)|sift_export|kernel/export\.sh' "$ROOT/bin/sift" 2>/dev/null \
  || fail "no 'sift export' verb (RED until implemented)"
grep -qiE '\-\-bundle|audit.*bundle' "$ROOT/bin/sift" "$ROOT/kernel/audit.sh" "$ROOT/kernel/_audit.py" 2>/dev/null \
  || fail "no 'audit --bundle' path (RED until implemented)"

# 2. build a witness-bound terminal (UP-9 / TRUST-AUDIT-1 contract) in an isolated .harness.
#    Parameterised on the terminal state so we can carry a partially_confirmed (TRUST-AUDIT-1
#    made partially_confirmed an auditable, gradeable terminal).
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export SIFT_REPO_ROOT="$W" SIFT_LOG="$W/.harness/log.jsonl" SIFT_REVIEWS="$W/.harness/reviews"
mkdir -p "$SIFT_REVIEWS"; . "$ROOT/kernel/log.sh"; . "$ROOT/kernel/state.sh"
_sha(){ python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
mkterminal(){ local P="$1" TO="$2" FS="${3:-abc}"   # FS = the feature_sha the terminal binds
  printf '{"verdict":"pass","confidence":0.9}\n' > "$SIFT_REVIEWS/$P.w3.json"
  printf '{"w2":"reproduced"}\n'                 > "$SIFT_REVIEWS/$P.w2.json"
  printf '{"ok":true}\n'                          > "$SIFT_REVIEWS/$P.w4.json"
  printf 'pkt %s\n' "$P"                          > "$SIFT_REVIEWS/$P.packet"
  local h2 h3 h4 eh; h2=$(_sha "$SIFT_REVIEWS/$P.w2.json"); h3=$(_sha "$SIFT_REVIEWS/$P.w3.json")
  h4=$(_sha "$SIFT_REVIEWS/$P.w4.json"); eh=$(_sha "$SIFT_REVIEWS/$P.packet")
  for e in "submitted packeted" "packeted executing" "executing acceptance_met" "acceptance_met reviewing"; do
    set -- $e; log_append lane.transition "$1" "$2" "$P" >/dev/null; done
  local vj veh we
  vj="$(python3 -c 'import json,sys;print(json.dumps({"verdict":"pass","feature_sha":sys.argv[4],"w2_hash":sys.argv[1],"w3_hash":sys.argv[2],"w4_hash":sys.argv[3]}))' "$h2" "$h3" "$h4" "$FS")"
  veh="$(log_append review.verdict reviewing reviewing "$P" "$vj")"
  we="$(python3 -c 'import json,sys;print(json.dumps({"verdict_event":sys.argv[1],"feature_sha":sys.argv[6],"extended_hash":sys.argv[5],"w1_ok":True,"w2_hash":sys.argv[2],"w3_hash":sys.argv[3],"w4_hash":sys.argv[4]}))' "$veh" "$h2" "$h3" "$h4" "$eh" "$FS")"
  log_append lane.transition reviewing "$TO" "$P" "$we" >/dev/null
}
# HARDENED: the carried terminal is a partially_confirmed (soft-floored, witness-bound).
mkterminal soft partially_confirmed
[ "$(SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" state soft 2>/dev/null)" = partially_confirmed ] \
  || fail "scaffold broken: did not build a genuine witness-bound partially_confirmed"

# 3. export -> a single bundle file.
B="$W/soft.bundle"
SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" export soft > "$B" 2>/dev/null || fail "sift export did not produce a bundle"
[ -s "$B" ] || fail "export bundle is empty"

# 4. verify on a FOREIGN machine: a clean temp dir with NO .harness / NO other repo state.
#    Routes through audit.sh's exact 3-check order against the bundle's contents alone.
C="$(mktemp -d)"
[ ! -e "$C/.harness" ] || fail "scaffold broken: foreign dir is not clean"
( cd "$C" && SIFT_REPO_ROOT="$C" bash "$ROOT/bin/sift" audit --bundle "$B" >/dev/null 2>&1 ) \
  || fail "audit --bundle FAILED a genuine partially_confirmed on a foreign machine"

# Locate a known byte run inside the bundle and flip ONE byte in place (length-preserving,
# format-agnostic: works whether the bundle is a tar or a framed JSON). NEEDLE is a literal
# string present in either a log line or an artifact carried by the bundle.
flip_in_place(){ local SRC="$1" DST="$2" NEEDLE="$3"
  python3 - "$SRC" "$DST" "$NEEDLE" <<'PY'
import sys
src, dst, needle = sys.argv[1], sys.argv[2], sys.argv[3].encode()
b = bytearray(open(src, "rb").read())
i = b.find(needle)
if i < 0:
    sys.stderr.write("needle not found in bundle\n"); sys.exit(2)
# flip one byte of the matched content (keep length, mutate value) so the embedded
# member still decodes but its bytes no longer hash to the bound value / chain.
b[i] ^= 0x20
open(dst, "wb").write(bytes(b))
PY
}

# precondition: both needles must EXIST inside a genuine bundle, else the tamper is vacuous.
# A LOG-LINE needle (the chained terminal token) and an ARTIFACT needle (the .w3 body).
LOG_NEEDLE='partially_confirmed'                 # appears in the bundle's log slice
ART_NEEDLE='{"verdict":"pass","confidence":0.9}' # the exact .w3.json artifact body
python3 - "$B" "$LOG_NEEDLE" "$ART_NEEDLE" <<'PY' || fail "scaffold broken: tamper needles absent from a genuine bundle (cannot prove in-content tamper)"
import sys
b = open(sys.argv[1], "rb").read()
sys.exit(0 if (sys.argv[2].encode() in b and sys.argv[3].encode() in b) else 1)
PY

# 5a. IN-CONTENT tamper #1 — flip a byte of a LOG LINE inside the bundle. MUST FAIL
#     (chain re-derivation catches it).
BT1="$W/tamper_log.bundle"; flip_in_place "$B" "$BT1" "$LOG_NEEDLE" || fail "scaffold broken: could not flip a log-line byte"
cmp -s "$B" "$BT1" && fail "scaffold broken: log tamper produced an identical bundle"
if ( cd "$C" && SIFT_REPO_ROOT="$C" bash "$ROOT/bin/sift" audit --bundle "$BT1" >/dev/null 2>&1 ); then
  fail "audit --bundle PASSED a bundle with an in-content LOG-LINE byte flipped (chain check must catch it)"
fi

# 5b. IN-CONTENT tamper #2 — swap an ARTIFACT's (.w3.json) bytes inside the bundle. MUST FAIL
#     (artifact re-hash catches it).
BT2="$W/tamper_art.bundle"; flip_in_place "$B" "$BT2" "$ART_NEEDLE" || fail "scaffold broken: could not swap an artifact byte"
cmp -s "$B" "$BT2" && fail "scaffold broken: artifact tamper produced an identical bundle"
if ( cd "$C" && SIFT_REPO_ROOT="$C" bash "$ROOT/bin/sift" audit --bundle "$BT2" >/dev/null 2>&1 ); then
  fail "audit --bundle PASSED a bundle with an in-content ARTIFACT byte swapped (re-hash must catch it)"
fi

# 6. CROSS-REPO PROVENANCE (the flagship gap, advisory but VISIBLE). A bundle's feature_sha
#    must be resolved against the repo audit runs in and surfaced PRESENT vs NOT-FOUND —
#    otherwise a bundle from repo A verifies next to unrelated repo B while the auditor
#    believes it vouches for the code in front of them. RED on HEAD: audit prints no
#    feature_sha provenance at all, so the NOT-FOUND/PRESENT distinction does not exist.
#
# 6a. NOT-FOUND: the existing 'soft' bundle binds feature_sha 'abc', audited in the foreign
#     $C which has no such commit -> audit must surface feature_sha as NOT-FOUND (the
#     cross-repo warning), not a silent clean pass.
prov_foreign="$( cd "$C" && SIFT_REPO_ROOT="$C" bash "$ROOT/bin/sift" audit --bundle "$B" 2>&1 || true )"
printf '%s' "$prov_foreign" | grep -qiE 'feature_sha' \
  || fail "audit --bundle surfaces NO feature_sha provenance (RED: no cross-repo binding — a bundle from another repo verifies here unflagged)"
printf '%s' "$prov_foreign" | grep -qiE 'not.?found|not in (this )?repo|unverified|absent|cannot resolve|unknown to this repo' \
  || fail "audit --bundle did not flag feature_sha NOT-FOUND in a foreign repo lacking the commit (RED: the cross-repo gap — bundle from repo A passes next to unrelated repo B with no warning)"

# 6b. PRESENT: a bundle whose feature_sha IS a real commit in the audit repo reports it bound.
G="$(mktemp -d)"
( cd "$G" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base ) || fail "scaffold: could not init the present-case git repo"
FS="$( cd "$G" && git rev-parse HEAD )"
rm -f "$SIFT_LOG"; rm -rf "$SIFT_REVIEWS"; mkdir -p "$SIFT_REVIEWS"
mkterminal bound confirmed "$FS"
BG="$W/bound.bundle"; SIFT_REPO_ROOT="$W" bash "$ROOT/bin/sift" export bound > "$BG" 2>/dev/null || fail "export(bound) did not produce a bundle"
prov_present="$( cd "$G" && SIFT_REPO_ROOT="$G" bash "$ROOT/bin/sift" audit --bundle "$BG" 2>&1 || true )"
printf '%s' "$prov_present" | grep -qiE 'present|found|bound to|in (this )?repo|HEAD' \
  || fail "audit --bundle did not report feature_sha PRESENT when it IS a commit in the audit repo (provenance must distinguish present vs not-found, not stay silent)"
rm -rf "$G"

# 7. PROVENANCE ANTI-SPOOF: bundle.json is unsigned metadata, so the feature_sha provenance must
#    come from the CHAIN-AUTHENTICATED terminal event in the carried log, NOT bundle.json. Rewrite
#    the bundle's bundle.json feature_sha to a spoofed value (the chain is untouched, so the bundle
#    still verifies) and confirm the provenance line ignores the spoof.
BSP="$W/spoof.bundle"
python3 - "$B" "$BSP" <<'PY' || fail "scaffold: could not repack bundle for the spoof test"
import tarfile, io, json, sys
src, dst = sys.argv[1], sys.argv[2]
t = tarfile.open(src); out = tarfile.open(dst, "w")
for m in t.getmembers():
    data = t.extractfile(m).read() if m.isfile() else b""
    if m.name == "bundle.json":
        d = json.loads(data); d["feature_sha"] = "SPOOFED0000spoof"; data = (json.dumps(d) + "\n").encode()
    ti = tarfile.TarInfo(m.name); ti.size = len(data); ti.mode = 0o644
    out.addfile(ti, io.BytesIO(data))
out.close(); t.close()
PY
prov_spoof="$( cd "$C" && SIFT_REPO_ROOT="$C" bash "$ROOT/bin/sift" audit --bundle "$BSP" 2>&1 || true )"
printf '%s' "$prov_spoof" | grep -q 'SPOOFED0000spoof' \
  && fail "the feature_sha provenance used the UNSIGNED bundle.json value (spoofable) — it must read the chain-authenticated terminal event"
printf '%s' "$prov_spoof" | grep -qiE 'feature_sha' \
  || fail "audit --bundle on the spoofed bundle surfaced no feature_sha provenance at all"

echo "PASS: sift export produces a portable bundle carrying a partially_confirmed; audit --bundle verifies it on a foreign machine, fails BOTH an in-content log-line flip and an artifact byte-swap, surfaces feature_sha cross-repo provenance (NOT-FOUND foreign, PRESENT in-repo), and reads the chain-authenticated feature_sha (a spoofed bundle.json is ignored)"
