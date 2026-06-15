#!/usr/bin/env bash
# Acceptance for W2-WORKTREE. RED on HEAD: W2 reproduces IN PLACE on the working tree, so an
# acceptance that depends on an UNTRACKED file (present in the tree, absent from the committed
# feature_sha) confirms. GREEN: W2 runs from a git worktree of feature_sha, where the untracked
# file does not exist, so that packet does NOT confirm; a fully-committed packet still does.
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SIFT="$ROOT/bin/sift"
fail(){ echo "FAIL: $*" >&2; exit 1; }
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS 2>/dev/null || true
command -v git >/dev/null 2>&1 || { echo "PASS (skipped: no git)"; exit 0; }

W="$(mktemp -d)"; trap 'git -C "$W" worktree prune 2>/dev/null; rm -rf "$W"' EXIT
export SIFT_REPO_ROOT="$W" SIFT_LOG="$W/.harness/log.jsonl" SIFT_STATE="$W/.harness" \
       SIFT_REVIEWS="$W/.harness/reviews" SIFT_PACKETS="$W/tasks/packets"
( cd "$W"; git init -q; git config user.email t@t; git config user.name t )
mkdir -p "$W/tasks/packets" "$W/out" "$W/.harness/reviews"
printf '.harness/\nscratch/\n' > "$W/.gitignore"

# --- packet whose acceptance needs a COMMITTED deliverable AND an UNTRACKED file. ----------
# rt.sh (committed) passes iff out/wt.txt carries the marker (committed) AND scratch/extra
# exists. scratch/ is gitignored+untracked, so it is NOT in a worktree of feature_sha.
cat > "$W/rt.sh" <<'SH'
#!/usr/bin/env bash
[ -f out/wt.txt ] && grep -q WT-OK out/wt.txt && [ -f scratch/extra ]
SH
cat > "$W/tasks/packets/wt.md" <<'MD'
---
id: wt
profile: software
goal: reproduce probe
test: rt.sh
wiring_exempt: true
---
MD
printf 'WT-OK\n' > "$W/out/wt.txt"
( cd "$W"; git add rt.sh tasks/packets/wt.md out/wt.txt; git commit -qm base )
# the untracked dependency: present in the working tree, NEVER committed.
mkdir -p "$W/scratch"; printf 'x\n' > "$W/scratch/extra"

bash "$SIFT" plan wt    >/dev/null 2>&1 || fail "scaffold: plan wt failed"
bash "$SIFT" execute wt >/dev/null 2>&1 || fail "scaffold: execute wt failed (in-place acceptance should pass: untracked file present)"
[ "$(bash "$SIFT" state wt)" = acceptance_met ] || fail "scaffold: wt not acceptance_met (is $(bash "$SIFT" state wt))"
# tree is clean of TRACKED changes (scratch + .harness are gitignored/untracked) -> review proceeds.
bash "$SIFT" review wt >/dev/null 2>&1 || true
st="$(bash "$SIFT" state wt)"
[ "$st" != confirmed ] \
  || fail "wt CONFIRMED despite its acceptance depending on an UNTRACKED file absent from feature_sha (RED: W2 reproduces in-place, not from a clean worktree of the commit)"

# --- positive control: a FULLY-COMMITTED packet still confirms (worktree reproduce passes). -
cat > "$W/rt2.sh" <<'SH'
#!/usr/bin/env bash
[ -f out/ok.txt ] && grep -q OK2 out/ok.txt
SH
cat > "$W/tasks/packets/ok.md" <<'MD'
---
id: ok
profile: software
goal: committed probe
test: rt2.sh
wiring_exempt: true
---
MD
printf 'OK2\n' > "$W/out/ok.txt"
( cd "$W"; git add rt2.sh tasks/packets/ok.md out/ok.txt; git commit -qm ok )
bash "$SIFT" plan ok    >/dev/null 2>&1 || fail "scaffold: plan ok failed"
bash "$SIFT" execute ok >/dev/null 2>&1 || fail "scaffold: execute ok failed"
bash "$SIFT" review ok  >/dev/null 2>&1 || true
[ "$(bash "$SIFT" state ok)" = confirmed ] \
  || fail "a fully-committed packet did not confirm from a clean worktree (over-strict: $(bash "$SIFT" state ok))"

# --- positive control: a GITIGNORED test oracle (this harness's own shape) still confirms. ---
# The packet's `test` lives under a gitignored dir, so it is ABSENT from the worktree of
# feature_sha. The W2 must copy the test oracle into the worktree (the test verifies the
# committed feature; it is not feature state) so a committed-feature packet still confirms.
# Without the copy, every software packet in a repo that gitignores its tests would fail W2.
printf 'evals/\n' >> "$W/.gitignore"
mkdir -p "$W/evals/snapshots/gi"
cat > "$W/evals/snapshots/gi/test.sh" <<'SH'
#!/usr/bin/env bash
[ -f out/gi.txt ] && grep -q GI-OK out/gi.txt
SH
cat > "$W/tasks/packets/gi.md" <<'MD'
---
id: gi
profile: software
goal: committed probe with a gitignored test oracle
test: evals/snapshots/gi/test.sh
wiring_exempt: true
---
MD
printf 'GI-OK\n' > "$W/out/gi.txt"
( cd "$W"; git add .gitignore tasks/packets/gi.md out/gi.txt; git commit -qm gi )   # test stays gitignored
[ -z "$(cd "$W" && git ls-files evals/)" ] || fail "scaffold: the gi test should be gitignored (not committed)"
bash "$SIFT" plan gi    >/dev/null 2>&1 || fail "scaffold: plan gi failed"
bash "$SIFT" execute gi >/dev/null 2>&1 || fail "scaffold: execute gi failed"
bash "$SIFT" review gi  >/dev/null 2>&1 || true
[ "$(bash "$SIFT" state gi)" = confirmed ] \
  || fail "a committed-feature packet with a GITIGNORED test oracle did not confirm — W2 must copy the test into the worktree (state: $(bash "$SIFT" state gi))"
[ "$(python3 -c 'import json;print(json.load(open("'"$W"'/.harness/reviews/gi.w2.json"))["mode"])' 2>/dev/null)" = clean_checkout ] \
  || fail "the gitignored-test packet did not record mode=clean_checkout (worktree path not taken)"

# --- security: a path-traversal `test:` (escaping the repo root) must be REJECTED ----------
# `test:` becomes `cd <root> && bash <test>` and is copied into the worktree, so an absolute or
# `..` path would read/execute/write OUTSIDE the clean checkout (a worktree-isolation bypass).
# Make it pass execute in-place (escape target one level above the repo), then review must
# fail-closed on the containment guard BEFORE running it.
ESC="$(dirname "$W")/esc-$$.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$ESC"
cat > "$W/tasks/packets/esc.md" <<MD
---
id: esc
profile: software
goal: traversal probe
test: ../$(basename "$ESC")
wiring_exempt: true
---
MD
( cd "$W"; git add tasks/packets/esc.md; git commit -qm esc )
bash "$SIFT" plan esc    >/dev/null 2>&1 || fail "scaffold: plan esc failed"
bash "$SIFT" execute esc >/dev/null 2>&1 || fail "scaffold: execute esc failed (the escape target should pass in-place at execute)"
[ "$(bash "$SIFT" state esc)" = acceptance_met ] || fail "scaffold: esc not acceptance_met (is $(bash "$SIFT" state esc))"
bash "$SIFT" review esc  >/dev/null 2>&1 || true
[ "$(bash "$SIFT" state esc)" != confirmed ] \
  || fail "a path-traversal test: ('../...') reached confirmed — review must reject a non-repo-contained test path before running it (worktree-isolation bypass)"
rm -f "$ESC"

echo "PASS: W2 reproduces from a clean worktree of feature_sha — untracked-dep does NOT confirm; committed + gitignored-oracle packets do (clean_checkout); a path-traversal test path is rejected"
