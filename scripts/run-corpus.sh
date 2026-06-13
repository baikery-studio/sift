#!/usr/bin/env bash
# scripts/run-corpus.sh — run the eval-snapshot acceptance corpus as a regression gate.
#
# Closes the "63 proofs run by nothing" gap: every snapshot whose packet has reached
# `confirmed` MUST still pass, so a confirmed packet's acceptance cannot silently rot.
# Snapshots whose packet is NOT confirmed are SKIPPED (an in-flight packet is RED-first by
# design; a stale/removed-feature snapshot has no confirmed packet). superseded/ is never
# run. The runner excludes its own gate packet to avoid recursion.
#
# Exit 0 if every confirmed-packet snapshot passes (or none apply); non-zero otherwise.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIFT="$ROOT/bin/sift"
SELF_PACKET="TQ-1-SNAPSHOT-GATE"

ran=0 skipped=0 failed=0 failures=""
for d in "$ROOT"/evals/snapshots/*/; do
  t="$d/test.sh"; [ -f "$t" ] || continue
  id="$(basename "$d")"
  [ "$id" = "superseded" ] && continue
  [ "$id" = "$SELF_PACKET" ] && { skipped=$((skipped+1)); continue; }
  st="$(SIFT_REPO_ROOT="$ROOT" "$SIFT" state "$id" 2>/dev/null || echo unknown)"
  if [ "$st" != confirmed ] && [ "$st" != partially_confirmed ]; then
    skipped=$((skipped+1)); continue
  fi
  if ( unset SIFT_LOG SIFT_STATE SIFT_PACKETS SIFT_REVIEWS; bash "$t" >/dev/null 2>&1 ); then
    ran=$((ran+1))
  else
    failed=$((failed+1)); failures="$failures $id"
  fi
done

echo "[corpus] confirmed-snapshot regression: ran=$ran passed=$((ran-0)) failed=$failed skipped=$skipped"
if [ "$failed" -gt 0 ]; then
  echo "[corpus] FAILED confirmed snapshots:$failures" >&2
  exit 1
fi
echo "[corpus] OK — every confirmed-packet snapshot still passes"
