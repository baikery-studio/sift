#!/usr/bin/env bash
# scripts/demo.sh — a 30-second, self-contained demo of sift's core claim:
# "done" is witness-bound, and a forged/premature "done" replays as corrupt.
# Runs in a throwaway dir, touches nothing in your repo. No deps beyond bash + python3.
set -euo pipefail
SIFT="$(cd "$(dirname "$0")/.." && pwd)/bin/sift"
W="$(mktemp -d)"; export SIFT_REPO_ROOT="$W"; trap 'rm -rf "$W"' EXIT
say(){ printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "1. a clean run reaches a witness-bound confirmed"
"$SIFT" setup >/dev/null
"$SIFT" packet new hello --profile toy >/dev/null 2>&1
mkdir -p "$W/out"; printf 'a scaffolded greeting\nhello-OK\n' > "$W/out/hello.txt"
"$SIFT" plan hello >/dev/null; "$SIFT" execute hello >/dev/null; "$SIFT" review hello >/dev/null
printf '   sift state hello -> %s\n' "$("$SIFT" state hello)"

say "2. you cannot fake it: hand-write a 'confirmed' with no real review"
python3 - "$W/.harness/log.jsonl" <<'PY'
import json,sys,hashlib,unicodedata
log=sys.argv[1]; lines=[l for l in open(log) if l.strip()]
last=json.loads(lines[-1]); prev=last["event_hash"]; seq=last["seq"]+1
ev={"kind":"lane.transition","from":"x","to":"confirmed","packet_id":"forged","seq":seq,"prev_hash":prev,"ts":"now"}
can=unicodedata.normalize("NFC",json.dumps(ev,sort_keys=True,separators=(",",":"),ensure_ascii=False))
ev["event_hash"]=hashlib.sha256(can.encode()).hexdigest()           # a VALID hash-chain link...
open(log,"a").write(json.dumps(ev)+"\n")                            # ...but no witnessed review behind it
PY
printf '   sift state forged -> %s   (the chain is valid, but the witness is missing)\n' "$("$SIFT" state forged)"

say "3. and tampering with the log is evident"
printf 'garbage\n' >> "$W/.harness/log.jsonl"
"$SIFT" verify-log || true

printf '\n\033[1mThat is the whole idea: completion is proven, not asserted.\033[0m\n'
