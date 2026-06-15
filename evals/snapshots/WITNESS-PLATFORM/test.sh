#!/usr/bin/env bash
# Acceptance for WITNESS-PLATFORM. RED on HEAD: the review witness set is hardcoded w2/w3/w4
# in pipeline.sh + _state.py, so a profile that DECLARES an extra witness (w5) has it ignored.
# GREEN: a declared w5 witness is invoked during review (writes its artifact) and bound in the
# confirmed event; the default w2/w3/w4 set still confirms byte-identically.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS 2>/dev/null || true
command -v git >/dev/null 2>&1 || { echo "PASS (skipped: no git)"; exit 0; }

# Copy the engine to a temp PLUGIN root so we can declare an extra witness in the software
# profile without touching the real tree. (selective copy: bin + kernel + profiles.)
P="$(mktemp -d)"; trap 'rm -rf "$P" "$R" 2>/dev/null' EXIT
mkdir -p "$P"; cp -R "$ROOT/bin" "$ROOT/kernel" "$ROOT/profiles" "$P/"
cp "$ROOT/VERSION" "$P/" 2>/dev/null || true
SIFT="$P/bin/sift"

# declare a 5th witness in the (copied) software profile + an impl that writes a sentinel.
python3 - "$P/profiles/software/profile.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
d["witnesses"]["w5"]={"impl":"witness_w5.sh","artifact":".w5.json"}
json.dump(d,open(p,"w"),indent=2)
PY
cat > "$P/profiles/software/witness_w5.sh" <<'SH'
#!/usr/bin/env bash
# extra declared witness: writes its artifact + a sentinel, returns ok.
set -euo pipefail
id="$2"; reviews="${SIFT_REVIEWS:-.harness/reviews}"; mkdir -p "$reviews"
printf '{"w5":"ran"}\n' > "$reviews/$id.w5.json"
: > "${SIFT_W5_SENTINEL:-/dev/null}"
printf '{ "ok": true, "reason": "w5 declared witness ran" }\n'
SH

# minimal software packet that reaches review in a git repo.
R="$(mktemp -d)"
export SIFT_REPO_ROOT="$R" SIFT_LOG="$R/.harness/log.jsonl" SIFT_STATE="$R/.harness" \
       SIFT_REVIEWS="$R/.harness/reviews" SIFT_PACKETS="$R/tasks/packets" \
       SIFT_PLUGIN_ROOT="$P"
( cd "$R"; git init -q; git config user.email t@t; git config user.name t )
mkdir -p "$R/tasks/packets" "$R/.harness/reviews"
printf '.harness/\n' > "$R/.gitignore"
cat > "$R/rt.sh" <<'SH'
#!/usr/bin/env bash
true
SH
cat > "$R/tasks/packets/wp.md" <<'MD'
---
id: wp
profile: software
goal: witness-set probe
test: rt.sh
wiring_exempt: true
---
MD
( cd "$R"; git add rt.sh tasks/packets/wp.md .gitignore; git commit -qm base )

SENT="$R/w5.sentinel"
bash "$SIFT" plan wp    >/dev/null 2>&1 || fail "scaffold: plan wp failed"
bash "$SIFT" execute wp >/dev/null 2>&1 || fail "scaffold: execute wp failed"
SIFT_W5_SENTINEL="$SENT" bash "$SIFT" review wp >/dev/null 2>&1 || true

# 1. the declared w5 witness was INVOKED during review (its artifact + sentinel exist).
[ -f "$SIFT_REVIEWS/wp.w5.json" ] \
  || fail "the profile-declared w5 witness was NOT invoked during review (RED: pipeline.sh hardcodes w2/w3/w4 and ignores the declared witness set)"

# 2. w5 is BOUND in the confirmed event (witness_evidence carries w5_hash matching the artifact).
[ "$(bash "$SIFT" state wp 2>/dev/null)" = confirmed ] \
  || fail "wp did not confirm with the declared w5 witness (RED: declared witnesses are not run/bound)"
bound="$(python3 - "$SIFT_LOG" "$SIFT_REVIEWS/wp.w5.json" <<'PY'
import json,sys,hashlib
log,art=sys.argv[1],sys.argv[2]
want=hashlib.sha256(open(art,"rb").read()).hexdigest()
ok=1
for ln in open(log):
    ln=ln.strip()
    if not ln: continue
    e=json.loads(ln)
    if e.get("kind")=="lane.transition" and e.get("to")=="confirmed" and e.get("packet_id")=="wp":
        we=e.get("witness_evidence") or {}
        if we.get("w5_hash")==want: ok=0
print(ok)
PY
)"
[ "$bound" = 0 ] \
  || fail "the confirmed event does not bind w5_hash to the on-disk .w5.json (RED: _state.py enumerates a literal w2/w3/w4 list, not the declared witness set)"

# 3. an EXOTIC witness id the replay would not bind (a `.`/`/` in the id) must be REJECTED by
# the producer (review_failed), so a witness that runs is a witness replay verifies — no
# fail-open gap between "pipeline ran it" and "_state.py bound it".
python3 - "$P/profiles/software/profile.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
d["witnesses"]["w.evil"]={"impl":"witness_w5.sh","artifact":".w.evil.json"}
json.dump(d,open(p,"w"),indent=2)
PY
cat > "$R/tasks/packets/bad.md" <<'MD'
---
id: bad
profile: software
goal: exotic-witness-id probe
test: rt.sh
wiring_exempt: true
---
MD
( cd "$R"; git add tasks/packets/bad.md; git commit -qm bad )
bash "$SIFT" plan bad    >/dev/null 2>&1 || fail "scaffold: plan bad failed"
bash "$SIFT" execute bad >/dev/null 2>&1 || fail "scaffold: execute bad failed"
bash "$SIFT" review bad  >/dev/null 2>&1 || true
[ "$(bash "$SIFT" state bad 2>/dev/null)" != confirmed ] \
  || fail "a profile declaring an exotic witness id ('w.evil') reached confirmed — the producer must reject an id that replay would not bind (fail-open gap)"

echo "PASS: a profile-declared extra witness (w5) is invoked during review and bound in the confirmed event; an exotic witness id is rejected — the witness set is data-driven from profile.json"
