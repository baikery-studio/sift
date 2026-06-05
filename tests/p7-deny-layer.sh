#!/usr/bin/env bash
# selftest: the deny layer exists, is valid JSON, and covers the named classes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; S="$ROOT/.claude-plugin/settings.json"
[ -f "$S" ] || { echo "settings.json absent"; exit 1; }
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$S" || { echo "settings.json invalid JSON"; exit 1; }
blob="$(tr "[:upper:]" "[:lower:]" < "$S")"
for tok in sudo "rm -rf" "--force" "--no-verify" ".env" pem key 169.254.169.254; do
  case "$blob" in *"$tok"*) ;; *) echo "deny layer missing: $tok"; exit 1 ;; esac
done
echo "PASS: deny layer covers sudo/rm-rf/force-push/no-verify + secret files + metadata endpoint"
