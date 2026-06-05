#!/usr/bin/env bash
# selftest: the sift-workflow skill exists and references only real bin/sift verbs
# (anti-drift) — a skill can never teach a command that doesn't exist.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIFT="$ROOT/bin/sift"
SK="$ROOT/skills/sift-workflow/SKILL.md"
[ -f "$SK" ] || { echo "SKILL.md missing"; exit 1; }
realverbs="$(grep -oE '^  [a-z][a-z|"-]*\)' "$SIFT" | sed -E 's/^ +//; s/\)$//' | tr '|' '\n' | sed 's/"//g' | grep -vE '^\*?$' | sort -u)"
skillverbs="$(grep -oE '`sift +[a-z][a-z-]*' "$SK" | sed -E 's/^`sift +//' | sort -u)"
[ -n "$skillverbs" ] || { echo "SKILL.md references no sift verbs"; exit 1; }
for v in $skillverbs; do
  printf '%s\n' "$realverbs" | grep -qx "$v" || { echo "SKILL.md references 'sift $v' (not a real subcommand)"; exit 1; }
done
echo "PASS: sift-workflow skill present; every referenced verb is a real bin/sift subcommand (anti-drift)"
