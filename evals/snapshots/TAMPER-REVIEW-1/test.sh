#!/usr/bin/env bash
# Acceptance for TAMPER-REVIEW-1. RED on HEAD: the anti-test-tampering signature
# scan runs ONLY at execute time (kernel/pipeline.sh _signatures_gate, called once
# from sift_execute ~line 77) over just two files (the packet 'test' file + the
# snapshot test.sh). sift_review NEVER re-scans, so a TAMPER introduced into ANY
# other changed file AFTER execute reaches a clean 'confirmed'. Also: a weakened
# .sh sibling test is not even recognised as a test by kernel/_signatures.py
# (_TEST_NAME extensions are py|js|ts|jsx|tsx|go|rb|java|cs, no '.sh').
#
# This test proves BOTH defects:
#   1. A full plan->execute->review drive REACHES 'confirmed' even though a
#      committed changed file in the packet's base..HEAD set carries a TAMPER
#      signature that kernel/_signatures.py independently flags. The GREEN target
#      makes sift_review re-scan the changed set and REJECT (review_failed / state
#      != confirmed) on a TAMPER hit.
#   2. kernel/_signatures.py does not recognise a '.test.sh' file as a test, so a
#      weakened .sh test is invisible to the scan. GREEN adds '.sh' to _TEST_NAME.
# Two structural guards pin the NAMED defects so a scaffold bug or an over-broad
# change cannot be mistaken for (or hide) the defect.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS SIFT_REPO_ROOT 2>/dev/null || true

command -v git >/dev/null 2>&1 || fail "scaffold needs git on PATH"
SIFT="$ROOT/bin/sift"
[ -x "$SIFT" ] || [ -f "$SIFT" ] || fail "scaffold: bin/sift missing"

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cd "$W" || fail "scaffold: cannot cd to temp"
export SIFT_REPO_ROOT="$W"
git init -q .                || fail "scaffold: git init failed"
git config user.email t@t    || fail "scaffold: git config failed"
git config user.name  t      || fail "scaffold: git config failed"

bash "$SIFT" setup >/dev/null 2>&1 || fail "scaffold: 'sift setup' failed"
mkdir -p out tests

# ---------------------------------------------------------------------------
# Author a keyless toy packet (CI-safe, no LLM): plan->execute->review->confirmed.
# ---------------------------------------------------------------------------
cat > tasks/packets/tamper-review-probe.md <<'EOF'
---
id: tamper-review-probe
profile: toy
goal: produce a greeting artifact carrying the marker
artifact:
  path: out/e.txt
  marker: TR1-OK
---
EOF
printf 'a greeting produced end to end\nTR1-OK\n' > out/e.txt

# Baseline commit -> this becomes the packet base (HEAD~1). A clean checkout of
# feature_sha must be possible, so the tree is fully committed at each step.
git add -A && git commit -qm base || fail "scaffold: baseline commit failed"

# ---- PRECONDITION (control): a clean changed set confirms normally -----------
# Prove the keyless drive itself works end-to-end on this host before we test the
# defect, so a profile/host breakage cannot be misread as the defect.
git checkout -q -b control 2>/dev/null || true
bash "$SIFT" plan    tamper-review-probe >/dev/null 2>&1 || fail "scaffold: 'sift plan' failed (control)"
bash "$SIFT" execute tamper-review-probe >/dev/null 2>&1 || fail "scaffold: 'sift execute' failed (control)"
bash "$SIFT" review  tamper-review-probe >/dev/null 2>&1 || fail "scaffold: 'sift review' failed (control)"
[ "$(bash "$SIFT" state tamper-review-probe 2>/dev/null)" = confirmed ] \
  || fail "scaffold: clean control packet did not reach 'confirmed' — drive is broken, not the defect"

# Reset to a fresh repo for the defect run (the control left a confirmed in the log).
cd "$W" >/dev/null || true
rm -rf "$W"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cd "$W" || fail "scaffold: cannot cd to fresh temp"
export SIFT_REPO_ROOT="$W"
git init -q . && git config user.email t@t && git config user.name t || fail "scaffold: re-init failed"
bash "$SIFT" setup >/dev/null 2>&1 || fail "scaffold: re-setup failed"
mkdir -p out tests
cat > tasks/packets/tamper-review-probe.md <<'EOF'
---
id: tamper-review-probe
profile: toy
goal: produce a greeting artifact carrying the marker
artifact:
  path: out/e.txt
  marker: TR1-OK
---
EOF
printf 'a greeting produced end to end\nTR1-OK\n' > out/e.txt
git add -A && git commit -qm base || fail "scaffold: defect-run baseline commit failed"

# ---- The TAMPER: a weakened sibling test, committed into base..HEAD ----------
# A .sh test under tests/ with a commented-out 'assert' — kernel/_signatures.py
# flags this on a recognised test file. It rides in the SECOND commit, i.e. it is
# part of the packet's changed set (base = HEAD~1) but is NOT one of the two files
# the execute-time gate scans (packet 'test' + snapshot test.sh).
TAMPER_FILE="tests/sibling.sh"
{ printf '#!/usr/bin/env bash\n'
  printf '# weakened sibling test introduced after execute\n'
  printf '# assert critical_invariant == true\n'
} > "$TAMPER_FILE"
git add -A && git commit -qm "weaken sibling test" || fail "scaffold: tamper commit failed"

# SANITY/REGRESSION-GUARD: _signatures.py MUST independently flag this file. If it
# does not, the scenario is broken (wrong pattern / wrong path) and a later 'review
# confirmed' would be a false RED. This pins that the tamper is genuinely a TAMPER.
if python3 "$ROOT/kernel/_signatures.py" "$TAMPER_FILE" >/dev/null 2>&1; then
  fail "scaffold: tamper file is NOT flagged by _signatures.py — scenario broken, not the defect"
fi
# And it IS in the packet's committed changed set.
git diff --name-only HEAD~1 HEAD 2>/dev/null | grep -qx "$TAMPER_FILE" \
  || fail "scaffold: tamper file not in base..HEAD changed set"

# ---- DEFECT 1: review must NOT reach 'confirmed' with a tamper in the set -----
bash "$SIFT" plan    tamper-review-probe >/dev/null 2>&1 || fail "scaffold: 'sift plan' failed (defect run)"
bash "$SIFT" execute tamper-review-probe >/dev/null 2>&1 \
  || fail "scaffold: 'sift execute' failed — execute-time gate scans only 2 files, must not block here"
bash "$SIFT" review  tamper-review-probe >/dev/null 2>&1 || true
st="$(bash "$SIFT" state tamper-review-probe 2>/dev/null)"
if [ "$st" = confirmed ]; then
  fail "review reached 'confirmed' with a TAMPER (weakened '$TAMPER_FILE') in the changed set (RED: sift_review never re-scans the diff with _signatures.py — defect #1)"
fi

# ---- STRUCTURAL GUARD for DEFECT 1: pin that review BLOCKED via the signature re-scan ------
# We only reach here when review did NOT confirm (the `if confirmed` above exits in the RED
# state). Pin that it blocked for the RIGHT reason: the state is review_failed (not some
# unrelated non-confirmed state) AND sift_review now references the _signatures re-scan. On
# HEAD (RED) this guard is never reached, so it is not a stale assertion.
[ "$st" = review_failed ] \
  || fail "review did not confirm but state is '$st', not 'review_failed' — the tamper must block via review_failed"
_rev_body="$(awk '/^sift_review\(\)/{f=1} f{print} f&&/^}/{exit}' "$ROOT/kernel/pipeline.sh")"
printf '%s' "$_rev_body" | grep -q 'sift_review' \
  || fail "scaffold: could not extract sift_review() body from kernel/pipeline.sh"
printf '%s' "$_rev_body" | grep -q '_signatures' \
  || fail "review_failed but sift_review does not reference the _signatures re-scan — blocked for the wrong reason, not the TAMPER-REVIEW-1 fix"

# ---- DEFECT 2: a '.sh' test file is recognised by _signatures.py --------------
# A weakened '.test.sh' OUTSIDE a tests/ dir is invisible today because _TEST_NAME
# omits '.sh'. (Inside tests/ it matches via the directory clause; this probe
# isolates the EXTENSION gap so the regex change is exercised.)
SH_PROBE="$W/weak.test.sh"
{ printf '#!/usr/bin/env bash\n'; printf '# assert recognised_as_test == true\n'; } > "$SH_PROBE"
if python3 "$ROOT/kernel/_signatures.py" "$SH_PROBE" >/dev/null 2>&1; then
  fail "_signatures.py does NOT recognise a '.test.sh' file as a test (RED: '.sh' missing from _TEST_NAME extensions — defect #2)"
fi

# ---- DEFECT 1 (degenerate): a SINGLE-COMMIT repo must still scan the shipped tree ----------
# When base_sha == feature_sha (no HEAD~1), there is no range to diff. The review scan must
# fall back to the whole tracked tree (the shipped set), so a tamper committed in the initial
# commit cannot pass unscanned (security review MEDIUM).
SC="$(mktemp -d)"; ( set -e
  cd "$SC"; export SIFT_REPO_ROOT="$SC"; git init -q .; git config user.email t@t; git config user.name t
  bash "$SIFT" setup >/dev/null 2>&1; mkdir -p out tests tasks/packets
  printf -- '---\nid: sc\nprofile: toy\ngoal: produce a greeting artifact carrying the marker\nartifact:\n  path: out/e.txt\n  marker: TR1-OK\n---\n' > tasks/packets/sc.md
  printf 'a greeting end to end\nTR1-OK\n' > out/e.txt
  printf '#!/usr/bin/env bash\n# assert critical == true\n' > tests/weak_test.sh   # tampered, shipped
  git add -A && git commit -qm only ) || fail "scaffold: single-commit repo setup failed"
[ "$(cd "$SC" && git rev-list --count HEAD)" = 1 ] || fail "scaffold: expected a single-commit repo"
SIFT_REPO_ROOT="$SC" bash "$SIFT" plan sc    >/dev/null 2>&1 || fail "scaffold: plan failed (single-commit)"
SIFT_REPO_ROOT="$SC" bash "$SIFT" execute sc >/dev/null 2>&1 || fail "scaffold: execute failed (single-commit)"
SIFT_REPO_ROOT="$SC" bash "$SIFT" review sc  >/dev/null 2>&1 || true
[ "$(SIFT_REPO_ROOT="$SC" bash "$SIFT" state sc 2>/dev/null)" != confirmed ] \
  || fail "single-commit repo: a tampered tracked test reached 'confirmed' (review must scan the whole tracked tree when there is no base..HEAD range)"
rm -rf "$SC"

# ---- DEFECT 1 (sandwich): clean -> tamper -> clean on the SAME file, all in base..HEAD ------
# The per-commit scan must snapshot each commit's version under a per-SHA path; otherwise (git
# log is newest-first) the final clean version overwrites the tampered middle commit on disk and
# the scan never sees the tamper. The feature commits land AFTER execute (commit-before-review),
# so base_sha is the pre-feature HEAD~1 and all three commits are inside the scanned range.
SW="$(mktemp -d)"; ( set -e
  cd "$SW"; export SIFT_REPO_ROOT="$SW"; git init -q .; git config user.email t@t; git config user.name t
  bash "$SIFT" setup >/dev/null 2>&1; mkdir -p out tests tasks/packets
  git add -A && git commit -qm c0                      # c0 so HEAD~1 (the base) exists
  printf -- '---\nid: sw\nprofile: toy\ngoal: produce a greeting artifact carrying the marker\nartifact:\n  path: out/e.txt\n  marker: TR1-OK\n---\n' > tasks/packets/sw.md
  printf 'a greeting end to end\nTR1-OK\n' > out/e.txt
  git add -A && git commit -qm baseline ) || fail "scaffold: sandwich repo setup failed"
SIFT_REPO_ROOT="$SW" bash "$SIFT" plan sw    >/dev/null 2>&1 || fail "scaffold: plan failed (sandwich)"
SIFT_REPO_ROOT="$SW" bash "$SIFT" execute sw >/dev/null 2>&1 || fail "scaffold: execute failed (sandwich)"
( set -e; cd "$SW"
  printf 'def test_x():\n    assert True\n' > tests/sneaky_test.py; git add -A && git commit -qm clean1
  printf 'import pytest\n@pytest.mark.skip\ndef test_x():\n    assert True\n' > tests/sneaky_test.py; git add -A && git commit -qm tamper
  printf 'def test_x():\n    assert True\n' > tests/sneaky_test.py; git add -A && git commit -qm clean2 ) \
  || fail "scaffold: sandwich commits failed"
SIFT_REPO_ROOT="$SW" bash "$SIFT" review sw >/dev/null 2>&1 || true
[ "$(SIFT_REPO_ROOT="$SW" bash "$SIFT" state sw 2>/dev/null)" != confirmed ] \
  || fail "sandwich (clean->tamper->clean same file) reached 'confirmed' — the per-commit snapshot must be SHA-namespaced so the tampered middle commit is scanned, not overwritten by the final clean version"
rm -rf "$SW"

echo "PASS: review re-scans the changed set (whole tree in a single-commit repo; per-commit SHA-namespaced so a clean->tamper->clean sandwich is caught) for tampers, rejects a weakened sibling, and .sh tests are recognised"
