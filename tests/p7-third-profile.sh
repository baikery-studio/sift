#!/usr/bin/env bash
# selftest: the prose (third, non-code) profile is DRIVABLE end-to-end via the real
# bin/sift — scaffold -> plan -> execute -> review -> confirmed — and an incomplete
# deliverable (missing a declared section) is review_failed, not confirmed. This is the
# strong genericity proof (UP-10), replacing the old file-existence/validate proxy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIFT="$ROOT/bin/sift"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"
unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS 2>/dev/null || true
export SIFT_REPO_ROOT="$work"
fail(){ echo "FAIL: $*" >&2; exit 1; }

bash "$SIFT" setup >/dev/null 2>&1 || fail "setup failed"

# 1. scaffold a prose packet — profile-correct (artifact.sections, deliverable in scope, no dead scope.type)
bash "$SIFT" packet new essay --profile prose >/dev/null 2>&1 || fail "packet new --profile prose failed"
pkt="$work/tasks/packets/essay.md"
grep -qiE 'sections' "$pkt" || fail "prose packet lacks artifact.sections"
grep -qE '^[[:space:]]*type:[[:space:]]*harness' "$pkt" && fail "dead scope.type:harness present"
grep -q 'out/essay.md' "$pkt" || fail "deliverable out/essay.md not in scope"

# 2. complete deliverable (both declared sections present) drives to confirmed
mkdir -p "$work/out"
printf '# Summary\nThe essay summary addresses the goal.\n\n# Detail\nThe detailed body.\n' > "$work/out/essay.md"
bash "$SIFT" plan essay    >/dev/null 2>&1 || fail "plan failed"
bash "$SIFT" execute essay >/dev/null 2>&1 || fail "execute failed (acceptance)"
bash "$SIFT" review essay  >/dev/null 2>&1 || fail "review failed (witnesses)"
[ "$(bash "$SIFT" state essay)" = confirmed ] || fail "prose essay not confirmed (got $(bash "$SIFT" state essay))"
echo "PASS 1: prose scaffold -> plan -> execute -> review -> confirmed (genericity earnable)"

# 3. negative: an incomplete deliverable (missing 'Detail') is review_failed, not confirmed
bash "$SIFT" packet new essay2 --profile prose >/dev/null 2>&1 || fail "packet new essay2 failed"
printf '# Summary\nonly the opening paragraph, nothing further.\n' > "$work/out/essay2.md"
bash "$SIFT" plan essay2    >/dev/null 2>&1 || fail "plan essay2 failed"
bash "$SIFT" execute essay2 >/dev/null 2>&1 || fail "execute essay2 failed (acceptance = nonempty)"
if bash "$SIFT" review essay2 >/dev/null 2>&1; then fail "incomplete prose reached confirmed (W4 should reject)"; fi
[ "$(bash "$SIFT" state essay2)" = review_failed ] || fail "incomplete prose not review_failed (got $(bash "$SIFT" state essay2))"
echo "PASS 2: incomplete prose deliverable -> review_failed (W4 section check has teeth)"

echo "ALL PROSE-SEAM ASSERTIONS PASS"
