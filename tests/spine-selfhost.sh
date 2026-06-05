#!/usr/bin/env bash
# Spine goal proof: the REAL bin/sift drives one packet plan→execute→review to a
# witness-bound `confirmed`; it reconstructs from the log alone; and a packet
# failing acceptance never reaches confirmed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"          # the sift-harness repo
SIFT="$ROOT/bin/sift"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"
export SIFT_REPO_ROOT="$work" \
       SIFT_LOG="$work/.harness/log.jsonl" \
       SIFT_REVIEWS="$work/.harness/reviews" \
       SIFT_STATE="$work/.harness" \
       SIFT_PACKETS="$work/tasks/packets"
mkdir -p tasks/packets out .harness/reviews
fail(){ echo "FAIL: $*" >&2; exit 1; }

cat > tasks/packets/toy-hello.md <<'EOF'
---
id: toy-hello
profile: toy
goal: produce a greeting artifact that carries the marker
artifact:
  path: out/hello.txt
  marker: HELLO-SIFT
---
A trivial toy packet for the spine self-host proof.
EOF
# the "worker" produces the artifact: a goal-addressing line (so toy W4's
# anti-stuffing check is satisfied) PLUS the marker on its own line.
printf 'a greeting produced by the spine\nHELLO-SIFT\n' > out/hello.txt

[ -n "$("$SIFT" version)" ] || fail "version empty"
echo "[v] sift version = $("$SIFT" version)"

"$SIFT" plan toy-hello    || fail "plan failed"
"$SIFT" execute toy-hello || fail "execute failed"
"$SIFT" review toy-hello  || fail "review failed"

st="$("$SIFT" state toy-hello)"
[ "$st" = confirmed ] || fail "expected confirmed, got '$st'"
echo "PASS 1: real bin/sift drove toy-hello → witness-bound confirmed"

# reconstruct from the log alone (fresh process; no in-memory state)
[ "$("$SIFT" state toy-hello)" = confirmed ] || fail "confirmed must rebuild from log.jsonl"
"$SIFT" verify-log >/dev/null || fail "log chain must verify"
echo "PASS 2: confirmed reconstructs from log.jsonl alone (compaction-survival)"

# negative: a packet whose artifact lacks the marker must NOT reach confirmed
cat > tasks/packets/toy-bad.md <<'EOF'
---
id: toy-bad
profile: toy
goal: produce a greeting artifact that carries the marker
artifact:
  path: out/bad.txt
  marker: HELLO-SIFT
---
EOF
printf 'no marker here\n' > out/bad.txt
"$SIFT" plan toy-bad
if "$SIFT" execute toy-bad; then fail "toy-bad must fail acceptance (no marker)"; fi
[ "$("$SIFT" state toy-bad)" = failed ] || fail "toy-bad should be 'failed'"
echo "PASS 3: packet failing acceptance → failed, never confirmed"

echo "ALL SPINE SELF-HOST ASSERTIONS PASS"
