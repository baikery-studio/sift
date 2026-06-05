#!/usr/bin/env bash
# Toy profile W4 witness — the "answers-the-goal" check.
#
# Contract (PROFILE_INTERFACE §3.3):
#   witness_w4(packet_path, packet_id, base_sha, feature_sha) -> { ok, reason }
#
# W4 IS A SEMANTIC WITNESS, NOT A STRUCTURAL/WIRING ONE. Where the software
# profile's W4 asks "is this symbol imported/mounted/rendered from production
# code" (code wiring), the toy profile's W4 asks an entirely different question
# in the same witness SLOT: "does the produced artifact actually ADDRESS the
# declared goal?" This deliberately mirrors how sift-DoE / sift-scientist W4 are
# semantic (answers-the-question), not structural — demonstrating that the
# witness slot carries a different job per profile. No software code-wiring
# concept (no import/callsite/route/render-presence heuristics, no path-roots,
# no boot-smoke) appears anywhere in this file.
#
# Fail-closed: any parse/IO failure returns ok:false. A witness that cannot read
# its inputs must reject, never pass.
set -euo pipefail

# --- minimal stdlib-only frontmatter reader (no PyYAML; fail-closed) ----------
# Extracts a scalar key from a leading `---`..`---` YAML block. Supports the two
# keys this toy witness needs: artifact.path, artifact.marker, and goal.
toy_w4_fm_get() {
  # toy_w4_fm_get <packet_path> <dotted.key>
  python3 - "$1" "$2" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
try:
    text = open(path, encoding="utf-8").read()
except OSError:
    sys.exit(3)
m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
if not m:
    sys.exit(4)
body = m.group(1)
# Tiny nested-scalar reader good enough for the toy schema (goal, artifact.path,
# artifact.marker). Tracks a single level of nesting by indentation.
parts = key.split(".")
cur_parent = None
val = None
for line in body.splitlines():
    mm = re.match(r"^(\s*)([A-Za-z0-9_]+):\s*(.*)$", line)
    if not mm:
        continue
    indent, k, rest = len(mm.group(1)), mm.group(2), mm.group(3).strip()
    if indent == 0:
        cur_parent = k
        if len(parts) == 1 and k == parts[0]:
            val = rest
    elif indent > 0 and len(parts) == 2 and cur_parent == parts[0] and k == parts[1]:
        val = rest
if val is None:
    sys.exit(5)
# strip surrounding quotes
val = val.strip()
if len(val) >= 2 and val[0] in "\"'" and val[-1] == val[0]:
    val = val[1:-1]
print(val)
PY
}

# --- path containment: reject an artifact.path that escapes the repo root -----
# A relative or ../-laden path must resolve to a location under SIFT_REPO_ROOT, so
# a packet can't satisfy `confirmed` by pointing at e.g. /etc/passwd.
toy_path_contained() { # <artifact_path> ; rc 0 if inside repo root
  python3 - "$1" "${SIFT_REPO_ROOT:-$(pwd)}" <<'PY'
import os, sys
art, root = sys.argv[1], sys.argv[2]
base = os.path.realpath(root)
full = os.path.realpath(art if os.path.isabs(art) else os.path.join(base, art))
sys.exit(0 if (full == base or full.startswith(base + os.sep)) else 1)
PY
}

# --- the semantic core: does the artifact ADDRESS the declared goal? ----------
# Trivial presence check (this is the toy: the witness slot's JOB differs per
# profile; here it is goal-addressing, NOT code-wiring). The artifact addresses
# the goal iff it contains the marker AND at least one salient word of the goal,
# i.e. evidence the artifact is about the goal and not marker-stuffing.
toy_w4_goal_addressed() {
  # toy_w4_goal_addressed <artifact_path> <marker> <goal>
  local artifact="$1" marker="$2" goal="$3"
  # resolve against SIFT_REPO_ROOT (not the caller's cwd)
  case "$artifact" in /*) ;; *) artifact="${SIFT_REPO_ROOT:-$(pwd)}/$artifact" ;; esac
  [ -f "$artifact" ] || { echo "artifact not found: $artifact"; return 1; }
  if ! grep -qF -- "$marker" "$artifact"; then
    echo "marker absent from artifact"
    return 1
  fi
  # Goal-addressing: at least one goal token (>=4 chars) appears in the artifact
  # CONTENT (with the marker line removed, so the marker string itself can never
  # satisfy goal-addressing — that would be marker-stuffing). Deliberately
  # semantic-not-structural: we check the artifact is ABOUT the goal, never that
  # a symbol is wired into code.
  local body tok addressed=0
  body="$(grep -vF -- "$marker" "$artifact" || true)"
  for tok in $goal; do
    if [ "${#tok}" -ge 4 ] && printf '%s' "$body" | grep -qiF -- "$tok"; then
      addressed=1
      break
    fi
  done
  if [ "$addressed" -ne 1 ]; then
    echo "marker present but artifact does not address the goal (stuffed)"
    return 2
  fi
  return 0
}

# --- contract entrypoint ------------------------------------------------------
witness_w4() {
  # witness_w4 <packet_path> <packet_id> <base_sha> <feature_sha>
  local packet_path="${1:-}"
  if [ -z "$packet_path" ] || [ ! -f "$packet_path" ]; then
    printf '{ "ok": false, "reason": "W4 packet not found (fail-closed)" }\n'
    return 1
  fi
  local artifact marker goal
  artifact="$(toy_w4_fm_get "$packet_path" artifact.path)"   || { printf '{ "ok": false, "reason": "W4 frontmatter parse failed (fail-closed)" }\n'; return 1; }
  marker="$(toy_w4_fm_get "$packet_path" artifact.marker)"   || { printf '{ "ok": false, "reason": "W4 frontmatter parse failed (fail-closed)" }\n'; return 1; }
  goal="$(toy_w4_fm_get "$packet_path" goal)"                || { printf '{ "ok": false, "reason": "W4 frontmatter parse failed (fail-closed)" }\n'; return 1; }

  local out rc
  set +e
  out="$(toy_w4_goal_addressed "$artifact" "$marker" "$goal")"; rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    printf '{ "ok": true, "reason": "artifact addresses the declared goal and contains the marker" }\n'
    return 0
  fi
  # JSON-escape the reason (it can carry a goal/marker substring with quotes)
  local rj; rj="$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$out")"
  printf '{ "ok": false, "reason": %s }\n' "$rj"
  return 1
}

# Allow direct invocation: witness_w4.sh <packet> <id> <base_sha> <feature_sha>
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  witness_w4 "$@"
fi
