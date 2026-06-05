#!/usr/bin/env bash
# kernel/config.sh — path resolver. Sourced by kernel scripts. Repo-root-relative
# (we build in our OWN repo, os/sift-harness; no `sift-harness/` staging prefix).
_SIFT_CFG="${SIFT_CONFIG:-${SIFT_REPO_ROOT:-$(pwd)}/sift-harness.config.json}"

config_path() {
  key="$1"
  case "$key" in
    state)     def=".harness" ;;
    log)       def=".harness/log.jsonl" ;;
    reviews)   def=".harness/reviews" ;;
    packets)   def="tasks/packets" ;;
    snapshots) def="evals/snapshots" ;;
    *)         def="" ;;
  esac
  # Resolve ABSOLUTE against the repo root (at CALL time). A relative path would
  # resolve against $(pwd), so `sift next` / witnesses / hooks read the WRONG log
  # when a host invokes them from any cwd other than the repo root. Closes the
  # cwd-dependence finding at its root.
  _cfg_abs() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "${SIFT_REPO_ROOT:-$(pwd)}" "$1" ;; esac; }
  if [ -f "$_SIFT_CFG" ]; then
    v=$(python3 -c 'import json,sys
try:
    c=json.load(open(sys.argv[1])); print((c.get("paths") or {}).get(sys.argv[2],""))
except Exception:
    print("")' "$_SIFT_CFG" "$key" 2>/dev/null)
    if [ -n "$v" ]; then _cfg_abs "$v"; return 0; fi
  fi
  _cfg_abs "$def"
}
