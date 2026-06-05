#!/usr/bin/env bash
# compaction-survival (criterion 5): long-horizon resume. Confirm 2 of a 3-member
# wave, then SIMULATE a context compaction — a brand-new process with the entire
# environment wiped (no SIFT_* carryover, nothing but the on-disk log) — and prove
# it recomputes the correct next actionable packet. State survives because it lives
# in the replayable append-only log, not in any agent's memory.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT; cd "$work"
export SIFT_REPO_ROOT="$work"
"$SIFT" setup >/dev/null
mkdir -p out tasks/waves

# A 3-member toy wave.
cat > tasks/waves/longhaul.json <<'EOF'
{"id":"longhaul","members":["lh-1","lh-2","lh-3"]}
EOF
for i in 1 2 3; do
  cat > "tasks/packets/lh-$i.md" <<EOF
---
id: lh-$i
profile: toy
goal: produce greeting artifact number $i carrying its marker
artifact:
  path: out/lh-$i.txt
  marker: LH-$i
---
EOF
  printf 'a greeting artifact produced for step %s\nLH-%s\n' "$i" "$i" > "out/lh-$i.txt"
done

# Confirm members 1 and 2 only; leave 3 in flight.
for i in 1 2; do
  "$SIFT" plan "lh-$i" >/dev/null
  "$SIFT" execute "lh-$i" >/dev/null
  "$SIFT" review "lh-$i" >/dev/null
  [ "$("$SIFT" state "lh-$i")" = confirmed ] || { echo "lh-$i not confirmed"; exit 1; }
done

# Resume point BEFORE compaction (warm process).
warm="$("$SIFT" next longhaul)"
[ "$warm" = "lh-3" ] || { echo "FAIL: warm resume expected lh-3, got '$warm'"; exit 1; }

# --- SIMULATED COMPACTION ---------------------------------------------------
# `env -i` wipes ALL inherited environment: a cold process with zero in-memory
# state. Only HOME/PATH (to find python3/git) and the repo root are reintroduced.
# Everything it knows about progress, it must re-derive from the log on disk.
cold="$(env -i HOME="$HOME" PATH="$PATH" SIFT_REPO_ROOT="$work" bash "$SIFT" next longhaul)"
[ "$cold" = "lh-3" ] || { echo "FAIL: post-compaction resume expected lh-3, got '$cold'"; exit 1; }

# And the confirmed history must reconstruct identically in the cold process.
for i in 1 2; do
  s="$(env -i HOME="$HOME" PATH="$PATH" SIFT_REPO_ROOT="$work" bash "$SIFT" state "lh-$i")"
  [ "$s" = confirmed ] || { echo "FAIL: lh-$i not reconstructed as confirmed (got '$s')"; exit 1; }
done

# The host adapter surfaces the same pointer for re-injection.
inj="$(bash "$ROOT/hooks/sessionstart.sh" longhaul)"
case "$inj" in *"lh-3"*) : ;; *) echo "FAIL: sessionstart adapter did not surface lh-3: $inj"; exit 1 ;; esac

echo "PASS: after a simulated compaction (cold process, log only), sift resumes the correct packet (lh-3) and reconstructs confirmed history"
