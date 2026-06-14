#!/usr/bin/env bash
# kernel/w3_verdict.sh — `sift w3-verdict <id> <staging-file> [--force]`
#
# The host-verdict review (SOTA-2 default under an agent host, zero egress: the agent in the
# loop is the reviewer) requires the agent's R1-R13 rubric verdict to land at
# .harness/reviews/<id>.w3.json — but kernel/scope_guard.sh HARD-DENIES every agent write under
# .harness/ ("the forge channel"), focus or not. A reviewer that holds the pen on its own
# provenance record is not a control, so the deny stays. This verb is the ONLY sanctioned door:
# the agent writes its verdict to an IN-SCOPE staging path it is allowed to write, and sift's
# OWN code validates the shape and lands the canonical artifact. The agent never touches
# .harness/ directly. The verb does NOT decide pass/fail semantics (that is W3 at review time +
# the W3-SEM-1 rubric-value check) — it only lands a well-formed verdict past the fence.
_W3V_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$_W3V_DIR/config.sh"

# Resolve the active profile's W3 witness (it owns the single-source, injection-resistant
# verdict validator). Default to software; fall back if config is absent/unparseable.
_w3v_profile() {
  local cfg="${SIFT_CONFIG:-${SIFT_REPO_ROOT:-$(pwd)}/sift-harness.config.json}" p=""
  if [ -f "$cfg" ]; then
    p="$(python3 -c 'import json,sys
try: print((json.load(open(sys.argv[1])) or {}).get("profile",""))
except Exception: print("")' "$cfg" 2>/dev/null)"
  fi
  printf '%s' "${p:-software}"
}

sift_w3_verdict() {
  local force=0 id="" stage="" a
  for a in "$@"; do
    case "$a" in
      --force)      force=1 ;;
      --help|-h)    echo "usage: sift w3-verdict <id> <staging-file> [--force] — validate an agent-authored W3 verdict from an in-scope staging path and land it at reviews/<id>.w3.json"; return 0 ;;
      -*)           echo "[sift] w3-verdict: unknown option '$a'" >&2; return 2 ;;
      *)            if [ -z "$id" ]; then id="$a"; elif [ -z "$stage" ]; then stage="$a"; else echo "[sift] w3-verdict: too many arguments" >&2; return 2; fi ;;
    esac
  done
  [ -n "$id" ] && [ -n "$stage" ] || { echo "[sift] usage: sift w3-verdict <id> <staging-file> [--force]" >&2; return 2; }
  # Sanitise the packet id: it becomes a filename under the reviews dir, so a traversal id
  # (../../etc/x) or any path separator must NOT be allowed to escape it. Restrict to the
  # packet-id charset (the same shape `sift packet new` accepts).
  case "$id" in
    *[!A-Za-z0-9._-]*|""|.|..|*..*) echo "[sift] w3-verdict: invalid packet id '$id' (allowed: A-Z a-z 0-9 . _ - ; no path separators)" >&2; return 2 ;;
  esac
  [ -f "$stage" ] || { echo "[sift] w3-verdict: staging file not found: $stage" >&2; return 1; }

  local reviews dest
  reviews="${SIFT_REVIEWS:-$(config_path reviews)}"
  dest="$reviews/$id.w3.json"
  # Refuse to clobber an existing verdict for this id unless --force (no silent overwrite of a
  # prior verdict). Checked BEFORE validation so an existing artifact is never re-examined.
  if [ -e "$dest" ] && [ "$force" -ne 1 ]; then
    echo "[sift] w3-verdict: $dest already exists; refusing to clobber a prior verdict (use --force)" >&2; return 1
  fi

  # Reject an oversized staging file before reading it (a rubric verdict is well under 64KB;
  # this bounds disk use in the reviews dir). `-f` above already excludes non-regular files
  # (e.g. a symlink to /dev/zero), so `wc -c` cannot hang here.
  local max_bytes=65536 sz
  sz="$(wc -c < "$stage" 2>/dev/null || echo 0)"
  if [ "$sz" -gt "$max_bytes" ]; then
    echo "[sift] w3-verdict: staging file too large ($sz bytes, max $max_bytes)" >&2; return 1
  fi

  # SNAPSHOT the staging bytes ONCE into a sift-owned temp under the reviews dir, then validate
  # AND land from that snapshot. The agent cannot write under .harness/ (the scope guard denies
  # it), so it cannot race the snapshot — this binds the validated bytes to the landed bytes and
  # closes the validate-then-reland TOCTOU (a staging file swapped between the two reads would
  # otherwise land an unvalidated verdict). The snapshot is removed on every exit path.
  mkdir -p "$reviews" 2>/dev/null || { echo "[sift] w3-verdict: cannot create reviews dir $reviews" >&2; return 1; }
  local snap
  snap="$(SIFT_W3V_REV="$reviews" python3 -c 'import os,tempfile; fd,p=tempfile.mkstemp(dir=os.environ["SIFT_W3V_REV"],suffix=".w3.stage"); os.close(fd); print(p)' 2>/dev/null)"
  [ -n "$snap" ] && [ -f "$snap" ] || { echo "[sift] w3-verdict: could not create a staging snapshot" >&2; return 1; }
  if ! cat "$stage" > "$snap" 2>/dev/null; then
    rm -f "$snap" 2>/dev/null || true; echo "[sift] w3-verdict: could not read staging file $stage" >&2; return 1
  fi

  # Validate the SNAPSHOT with sift's OWN code: parseable JSON, a single verdict object (a planted
  # second verdict is rejected by the injection-resistant parser), verdict==pass, confidence
  # present, rubric a complete R1-R13 dict. Delegated to the profile's witness_w3 --validate-file
  # so there is exactly ONE validator, the same one review-time W3 applies. Fail closed on any
  # malformed/double-verdict input — land NO artifact (and drop the snapshot).
  local w3sh res
  w3sh="$_W3V_DIR/../profiles/$(_w3v_profile)/witness_w3.sh"
  if [ ! -f "$w3sh" ]; then rm -f "$snap" 2>/dev/null || true; echo "[sift] w3-verdict: no W3 witness for the active profile ($w3sh)" >&2; return 1; fi
  res="$(bash "$w3sh" --validate-file "$snap" 2>/dev/null)"
  if [ "$res" != pass ]; then
    rm -f "$snap" 2>/dev/null || true
    echo "[sift] w3-verdict: staged verdict REFUSED (${res:-malformed}) — nothing written to $dest" >&2; return 1
  fi

  # Land the SAME snapshot atomically via sift's python (tmp + os.replace in the reviews dir), so
  # the agent never writes under .harness/ itself and a crash mid-write cannot leave a partial
  # artifact. We land the validated snapshot, not the agent-writable staging path.
  SIFT_W3V_SRC="$snap" SIFT_W3V_DEST="$dest" python3 -c '
import os, sys, json, tempfile
src = os.environ["SIFT_W3V_SRC"]; dest = os.environ["SIFT_W3V_DEST"]
d = json.load(open(src))                      # the validated snapshot; re-parse defensively
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dest) or ".", suffix=".w3.tmp")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(d, f, separators=(",", ":"), ensure_ascii=False); f.write("\n")
    os.replace(tmp, dest)
except Exception as e:
    try: os.unlink(tmp)
    except OSError: pass
    sys.stderr.write("land failed: %s\n" % e); sys.exit(1)
'; local landrc=$?
  rm -f "$snap" 2>/dev/null || true
  [ "$landrc" -eq 0 ] || { echo "[sift] w3-verdict: failed to land artifact at $dest" >&2; return 1; }
  echo "[sift] w3-verdict: landed $id verdict -> $dest"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then sift_w3_verdict "$@"; fi
