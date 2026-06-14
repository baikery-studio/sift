#!/usr/bin/env bash
# Acceptance for SCALE-MEMO. RED on HEAD: project_state re-verifies the whole chain on every
# call, so a doctor over K confirmed packets verifies the chain K times (O(P×N)), and there is
# no SIFT_VERIFY_TRACE hook. GREEN: verify ONCE per invocation (count==1), the O(P) factor is
# gone (ratio bounded, hardware-independent), and trust correctness is byte-identical.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS SIFT_VERIFY_TRACE 2>/dev/null || true

# ---- generator: a valid hash-chained log with K confirmed packets + filler to ~L events. --
# Replicates kernel/_log.py canonicalization EXACTLY so the chain + witness binding verify.
gen(){ # <repo> <K confirmed> <L total events>
  python3 - "$1" "$2" "$3" <<'PY'
import os, sys, json, hashlib, unicodedata
repo, K, L = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
reviews = os.path.join(repo, ".harness", "reviews"); os.makedirs(reviews, exist_ok=True)
log = os.path.join(repo, ".harness", "log.jsonl")
GEN = "0"*64
def canon(o): return unicodedata.normalize("NFC", json.dumps(o, sort_keys=True, separators=(",",":"), ensure_ascii=False))
def sha_file(p):
    with open(p,"rb") as f: return hashlib.sha256(f.read()).hexdigest()
out=[]; prev=GEN; seq=0
def emit(packet, kind, frm, to, we):
    global prev, seq
    seq += 1
    c={"seq":seq,"ts":"","packet_id":packet,"kind":kind,"from":frm,"to":to,
       "actor":"harness","witness_evidence":we,"prev_hash":prev,"log_schema_version":"2"}
    c["event_hash"]=hashlib.sha256(canon({k:v for k,v in c.items() if k!="event_hash"}).encode()).hexdigest()
    out.append(canon(c)); prev=c["event_hash"]; return c["event_hash"]
# K genuine witness-bound confirmed packets (each carries on-disk artifacts).
for i in range(K):
    P="c%d"%i
    open(os.path.join(reviews,P+".w3.json"),"w").write('{"verdict":"pass","confidence":0.9}\n')
    open(os.path.join(reviews,P+".w2.json"),"w").write('{"w2":"reproduced"}\n')
    open(os.path.join(reviews,P+".w4.json"),"w").write('{"ok":true}\n')
    open(os.path.join(reviews,P+".packet"),"w").write("pkt %s\n"%P)
    h2=sha_file(os.path.join(reviews,P+".w2.json")); h3=sha_file(os.path.join(reviews,P+".w3.json"))
    h4=sha_file(os.path.join(reviews,P+".w4.json")); eh=sha_file(os.path.join(reviews,P+".packet"))
    emit(P,"lane.transition","submitted","packeted",None)
    emit(P,"lane.transition","packeted","executing",None)
    emit(P,"lane.transition","executing","acceptance_met",None)
    emit(P,"lane.transition","acceptance_met","reviewing",None)
    veh=emit(P,"review.verdict","reviewing","reviewing",
             {"verdict":"pass","feature_sha":"abc","w2_hash":h2,"w3_hash":h3,"w4_hash":h4})
    emit(P,"lane.transition","reviewing","confirmed",
         {"verdict_event":veh,"feature_sha":"abc","extended_hash":eh,"w1_ok":True,
          "w2_hash":h2,"w3_hash":h3,"w4_hash":h4})
# filler chained events (a never-confirmed packet cycling executing<->failed) to pad to L.
while seq < L:
    emit("filler","lane.transition","executing","failed",None)
    if seq < L: emit("filler","lane.transition","failed","executing",None)
open(log,"w").write("\n".join(out)+"\n")
print(seq)
PY
}

# doctor wall-time in milliseconds for a freshly-generated repo with K confirmed at size L.
doctor_ms(){ # <K> <L>
  local d; d="$(mktemp -d)"; gen "$d" "$1" "$2" >/dev/null
  SIFT_REPO_ROOT="$d" bash "$ROOT/bin/sift" verify-log >/dev/null 2>&1 || { echo "GENBROKE"; rm -rf "$d"; return; }
  local t0 t1
  t0="$(python3 -c 'import time;print(int(time.time()*1000))')"
  SIFT_REPO_ROOT="$d" bash "$ROOT/bin/sift" doctor >/dev/null 2>&1 || true
  t1="$(python3 -c 'import time;print(int(time.time()*1000))')"
  rm -rf "$d"; echo $((t1 - t0))
}

# ---- 0. SANITY: the generator builds a verifying chain with genuine confirmeds. -----------
SD="$(mktemp -d)"; trap 'rm -rf "$SD"' EXIT
n="$(gen "$SD" 3 200)"
[ "$n" -ge 200 ] || fail "scaffold broken: generator produced $n events (< 200)"
SIFT_REPO_ROOT="$SD" bash "$ROOT/bin/sift" verify-log >/dev/null 2>&1 || fail "scaffold broken: generated chain does not verify"
[ "$(SIFT_REPO_ROOT="$SD" bash "$ROOT/bin/sift" state c0 2>/dev/null)" = confirmed ] \
  || fail "scaffold broken: generated packet c0 is not confirmed (witness binding wrong)"

# ---- 1. PRIMARY RED: ONE doctor over K confirmed packets verifies the chain exactly ONCE. -
# Needs the SIFT_VERIFY_TRACE hook + the per-invocation memo. HEAD: hook absent -> 0 lines.
VT="$SD/verify.trace"; : > "$VT"
SIFT_REPO_ROOT="$SD" SIFT_VERIFY_TRACE="$VT" bash "$ROOT/bin/sift" doctor >/dev/null 2>&1 || true
vcount="$(wc -l < "$VT" | tr -d ' ')"
[ "$vcount" = 1 ] \
  || fail "doctor over 3 confirmed packets verified the chain $vcount times, want exactly 1 (RED: no SIFT_VERIFY_TRACE hook + no per-invocation memo — project_state re-verifies on every call, O(P×N))"

# ---- 2. O(P)-REMOVED RATIO (hardware-independent): doctor(20 confirmed) <= ~3x doctor(2). --
# Same total log size L; only the confirmed-packet COUNT differs. O(P×N) -> ratio ~10x;
# memoized -> ~1x. The ratio cancels machine speed, so it is robust on slow/fast hosts.
L=9000
a="$(doctor_ms 2 "$L")"; b="$(doctor_ms 20 "$L")"
{ [ "$a" = GENBROKE ] || [ "$b" = GENBROKE ]; } && fail "scaffold broken: large-log generation failed"
[ "$a" -lt 5 ] && a=5   # floor to avoid divide-by-tiny noise on a very fast host
ratio_x10=$(( b * 10 / a ))
[ "$ratio_x10" -le 30 ] \
  || fail "doctor scales with confirmed-packet COUNT: 20-packet doctor is ${ratio_x10}/10 x the 2-packet doctor (>3x) — the O(P) re-verify factor is still present (RED: memoize the chain verify per invocation)"

# ---- 3. CORRECTNESS PRESERVED: the memo must NOT weaken detection. -------------------------
CD="$(mktemp -d)"; gen "$CD" 2 200 >/dev/null
# 3a. a content-tampered confirmed artifact is STILL caught by doctor.
printf '{"verdict":"pass","TAMPERED":true}\n' > "$CD/.harness/reviews/c0.w3.json"
if SIFT_REPO_ROOT="$CD" bash "$ROOT/bin/sift" doctor >/dev/null 2>&1; then
  rm -rf "$CD"; fail "doctor PASSED a content-tampered confirmed artifact (memo must cache the verified list, NEVER skip the per-packet witness re-hash)"
fi
rm -rf "$CD"
# 3b. a tampered LOG LINE still replays corrupt.
TD="$(mktemp -d)"; gen "$TD" 2 200 >/dev/null
python3 - "$TD/.harness/log.jsonl" <<'PY'
import sys
p=sys.argv[1]; ls=open(p).read().splitlines()
ls[0]=ls[0].replace('"c0"','"cX"',1); open(p,"w").write("\n".join(ls)+"\n")
PY
[ "$(SIFT_REPO_ROOT="$TD" bash "$ROOT/bin/sift" state c0 2>/dev/null)" = corrupt ] \
  || { rm -rf "$TD"; fail "a tampered log no longer replays as corrupt (memo broke tamper-evidence)"; }
rm -rf "$TD"

# ---- 3c. IN-PROCESS stale-cache TOCTOU: a length-preserving in-place log tamper with the
#         mtime RESTORED must still re-verify to corrupt within the SAME process (the cache key
#         includes ctime/ino, which os.utime cannot forge). Without it, the memo would return a
#         stale clean state for a now-tampered log inside a long-lived batch/drive process.
MD="$(mktemp -d)"; gen "$MD" 1 6 >/dev/null
SIFT_MEMO_LOG="$MD/.harness/log.jsonl" SIFT_MEMO_REV="$MD/.harness/reviews" python3 - "$ROOT" <<'PY' || fail "stale-cache TOCTOU: an in-place tamper with restored mtime was NOT re-verified (memo returned a stale clean state)"
import os, sys, importlib.util
spec = importlib.util.spec_from_file_location("_state", os.path.join(sys.argv[1], "kernel", "_state.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
log = os.environ["SIFT_MEMO_LOG"]; rev = os.environ["SIFT_MEMO_REV"]
s1 = m.project_state(log, "c0", rev)                       # cache MISS -> verify + cache
if s1 != "confirmed": sys.exit(1)                          # scaffold: c0 must start confirmed
st = os.stat(log); orig = (st.st_atime_ns, st.st_mtime_ns)
b = bytearray(open(log, "rb").read())
i = b.find(b"confirmed"); b[i] ^= 0x20                     # length-preserving in-place flip
open(log, "wb").write(bytes(b)); os.utime(log, ns=orig)    # restore mtime (size unchanged)
s2 = m.project_state(log, "c0", rev)                       # must NOT be a stale clean hit
sys.exit(0 if s2 == "corrupt" else 2)
PY
rm -rf "$MD"

# ---- 4. zero egress preserved. -----------------------------------------------------------
bash "$ROOT/tests/test-no-egress.sh" >/dev/null 2>&1 || fail "test-no-egress.sh regressed"

echo "PASS: project_state verifies the chain once per invocation (count==1); the O(P) re-verify factor is gone (ratio bounded, hardware-independent); a tampered artifact, a tampered log, and an in-process in-place-tamper-with-mtime-restore are all caught; zero egress preserved"
