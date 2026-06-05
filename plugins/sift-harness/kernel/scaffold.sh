#!/usr/bin/env bash
# kernel/scaffold.sh — `sift packet new <id> [--profile <name>]`.
# Writes a schema-valid packet (objective + goal + scope.paths + acceptance_tests +
# proof_artifact) drivable by bin/sift. Profile-specific task fields come from the
# profile's own profiles/<name>/scaffold.fields (the kernel stays profile-agnostic).
# bash 3.2 safe (no ${var^^}). Refuses to clobber an existing packet.
_SCAF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_SCAF_DIR/config.sh"
SIFT_PACKETS="${SIFT_PACKETS:-$(config_path packets)}"
SIFT_SNAPSHOTS="${SIFT_SNAPSHOTS:-$(config_path snapshots)}"

# sift_packet_validate <id> — validate a packet against the SIFT schema (stdlib).
sift_packet_validate() {
  local id="${1:-}"; [ -n "$id" ] || { echo "[sift] usage: sift packet validate <id>" >&2; return 2; }
  local pkt="$SIFT_PACKETS/$id.md"
  [ -f "$pkt" ] || { echo "[sift] no packet: $id" >&2; return 1; }
  python3 "$_SCAF_DIR/_validate.py" "$pkt" "${SIFT_PLUGIN_ROOT:-$(cd "$_SCAF_DIR/.." && pwd)}"
}

sift_scaffold() {
  local id="" profile="toy" paths_csv="" from_diff=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --profile) profile="${2:-toy}"; shift 2 ;;
      --profile=*) profile="${1#--profile=}"; shift ;;
      --paths) paths_csv="${2:-}"; shift 2 ;;           # ADO-2: seed scope.paths from a CSV/glob list
      --paths=*) paths_csv="${1#--paths=}"; shift ;;
      --from-diff) from_diff=1; shift ;;                # ADO-2: seed scope.paths from the working-tree diff
      -*) echo "[sift] unknown flag: $1" >&2; return 2 ;;
      *) [ -z "$id" ] && id="$1"; shift ;;
    esac
  done
  [ -n "$id" ] || { echo "[sift] usage: sift packet new <id> [--profile <name>]" >&2; return 2; }
  # an id is an identifier, not a path — reject traversal/metachars before any write
  case "$id" in
    .|..) echo "[sift] invalid id '$id' (reserved / path traversal)" >&2; return 2 ;;
    .*)   echo "[sift] invalid id '$id' (must not start with '.')" >&2; return 2 ;;
    *[!A-Za-z0-9._-]*) echo "[sift] invalid id '$id' (allowed: A-Za-z0-9 . _ -)" >&2; return 2 ;;
  esac
  # the profile is a directory name, not a path — reject traversal before the -d test
  # (defense-in-depth; the validator also rejects it, but don't even probe the FS)
  case "$profile" in
    *..* | */*) echo "[sift] invalid profile '$profile' (path traversal)" >&2; return 2 ;;
  esac
  local plug="${SIFT_PLUGIN_ROOT:-$(cd "$_SCAF_DIR/.." && pwd)}"
  [ -d "$plug/profiles/$profile" ] || { echo "[sift] unknown profile: $profile (no profiles/$profile/)" >&2; return 2; }
  local pkt="$SIFT_PACKETS/$id.md"
  [ -e "$pkt" ] && { echo "[sift] refuses to clobber existing packet: $pkt" >&2; return 1; }
  mkdir -p "$SIFT_PACKETS" "$SIFT_SNAPSHOTS/$id"

  # ADO-2: seed the work scope.paths from --paths (CSV/globs) or --from-diff (working tree),
  # else the default placeholder. The packet + acceptance paths are always added below. This
  # is a STARTING scope the author tightens; the scope guard fences to whatever is declared.
  local work_paths=""
  if [ "$from_diff" = 1 ]; then
    # ADO-4: exclude harness-managed noise so a seeded scope holds only the dev's real source
    # changes — .harness/ state, the config, packets/snapshots, and .git. Otherwise a repo that
    # already used sift sweeps log.jsonl/config/prior packets into scope (the chore just moved).
    work_paths="$( (cd "$SIFT_REPO_ROOT" 2>/dev/null && git diff --name-only 2>/dev/null; \
                    cd "$SIFT_REPO_ROOT" 2>/dev/null && git diff --name-only --cached 2>/dev/null) \
                   | awk 'NF' | sort -u \
                   | grep -vE '^(\.harness/|\.canary/|\.git/|sift-harness\.config\.json$|tasks/packets/|evals/snapshots/)' || true )"
    [ -n "$work_paths" ] || echo "[sift] --from-diff: no source changes (harness files excluded); using placeholder scope" >&2
  fi
  if [ -n "$paths_csv" ]; then
    work_paths="$(printf '%s' "$paths_csv" | tr ',' '\n' | awk 'NF{gsub(/^[ \t]+|[ \t]+$/,"");print}')"
  fi
  [ -n "$work_paths" ] || work_paths="out/$id.txt"

  local goal="scaffolded packet $id — replace this goal and produce the declared artifact"
  {
    cat <<EOF
---
schema_version: v1
harness_version: v1.0.0
id: $id
profile: $profile
objective: |
  TODO: state what $id proves.
goal: $goal
EOF
    # Profile-specific packet fields come from the PROFILE itself (profiles/<name>/
    # scaffold.fields, with __ID__ substituted), NOT from kernel branching — so a new
    # profile scaffolds correctly with zero kernel edits. Falls back to a generic
    # placeholder if a profile ships no template.
    if [ -f "$plug/profiles/$profile/scaffold.fields" ]; then
      sed "s/__ID__/$id/g" "$plug/profiles/$profile/scaffold.fields"
    else
      printf '# (profile %s declares no scaffold.fields — add this profile'"'"'s required task fields here)\n' "$profile"
    fi
    printf 'scope:\n  type: harness\n  paths:\n'
    printf '%s\n' "$work_paths" | while IFS= read -r _p; do [ -n "$_p" ] && printf '    - %s\n' "$_p"; done
    printf '    - tasks/packets/%s.md\n    - evals/snapshots/%s/test.sh\n' "$id" "$id"
    cat <<EOF
require_red_first: true
acceptance_tests:
  - type: command
    description: "TODO: what $id proves"
    script: evals/snapshots/$id/test.sh
proof_artifact: {path: evals/snapshots/$id/proof.json, required_terminal_event: $id.done}
commit_policy: {squash_to: main, conventional: true, prefix_required: feat, reject_if_diff_touches_outside_scope: true}
---

# $id

TODO: describe the work, then:
  produce the declared artifact, and run
  sift plan $id && sift execute $id && sift review $id
EOF
  } > "$pkt"

  cat > "$SIFT_SNAPSHOTS/$id/test.sh" <<EOF
#!/usr/bin/env bash
# Acceptance for $id — RED until you implement it (replace the failing line).
# WEAK ACCEPTANCE STUB — replace with a real check before trusting confirmed.
# A grep for a marker passes on an empty file; run your actual test (npm test / pytest /
# go test / make) and assert the new behavior is wired. \`sift doctor\` flags this stub.
set -euo pipefail
echo "TODO: assert $id's acceptance criteria" >&2
exit 1
EOF
  chmod +x "$SIFT_SNAPSHOTS/$id/test.sh"
  echo "[sift] scaffolded $pkt + $SIFT_SNAPSHOTS/$id/test.sh (profile: $profile)"
  echo "[sift] WARNING: $id's acceptance is a WEAK placeholder stub — replace it with a real test before you trust \`confirmed\` (\`sift doctor\` will flag it until you do)." >&2
}

# sift_init_claudemd — write/append a fenced sift standing-rule block to the repo's CLAUDE.md
# (ADO-3, the hard-law option). A repo CLAUDE.md is a USER instruction and outranks the
# SessionStart primer's host-injected context, so this is for repos that want sift as law.
# Idempotent: a sentinel marker prevents a duplicate block on re-run; creates CLAUDE.md if absent.
sift_init_claudemd() {
  local f="$SIFT_REPO_ROOT/CLAUDE.md"
  if [ -f "$f" ] && grep -q 'sift-harness:standing-rule' "$f"; then
    echo "[sift] CLAUDE.md already carries the sift standing rule — no change (idempotent)"; return 0
  fi
  { [ -f "$f" ] && printf '\n'; cat <<'BLOCK'
<!-- sift-harness:standing-rule (managed block; edit the prose, keep the markers) -->
## Build rigor — use the sift harness

Drive every multi-step change, and any fix that must be verified, through sift rather than
freehanding it: scaffold a packet -> plan -> execute -> review -> witness-bound `confirmed`.
Do NOT report a task done until `sift state <id>` is `confirmed` — completion is witness-bound,
not asserted. Edits are fenced to the active packet's `scope.paths`.
<!-- /sift-harness:standing-rule -->
BLOCK
  } >> "$f"
  echo "[sift] wrote the sift standing rule to $f"
}
