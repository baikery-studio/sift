#!/usr/bin/env bash
# hooks/pretooluse-scope.sh — PreToolUse host adapter (Phase-2 runtime scope guard).
# Reads the host's PreToolUse JSON on stdin ({tool_name, tool_input:{file_path}})
# and BLOCKS (exit 2 + stderr reason) an edit whose path is outside the active
# packet's scope.paths. Exits 0 (allow) otherwise.
#
# ADVISORY: this only protects when the host runs the hook. Wire it in Claude Code
# via .claude/settings.json PreToolUse; other CLIs via their pre-tool equivalent.
# It is not a kernel-level sandbox.
#
# Installed as a plugin, hooks/hooks.json wires this via ${CLAUDE_PLUGIN_ROOT}.
# Manual (non-plugin) wiring in .claude/settings.json, co-located in the repo:
#   {"hooks":{"PreToolUse":[{"matcher":"Edit|Write|MultiEdit|NotebookEdit",
#     "hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse-scope.sh"}]}]}}
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export SIFT_REPO_ROOT="${CLAUDE_PROJECT_DIR:-${SIFT_REPO_ROOT:-$(pwd)}}"
. "$HOOK_DIR/../kernel/scope_guard.sh"

payload="$(cat 2>/dev/null || true)"
# Parse defensively. For edit tools we check file_path; for Bash we extract the
# command's WRITE TARGET(S) — redirections (`>`, `>>`) and write-capable commands
# (tee/cp/mv/install/truncate/touch/rsync/dd, sed -i) — and check EACH against scope.
# fd-dups (2>&1) and /dev/null are not file writes. A garbled payload yields
# __PARSE_ERROR__ so the guard fails CLOSED while a focus is active.
parsed="$(printf '%s' "$payload" | python3 -c 'import json,sys,re
# A Bash command whose write targets a regex CANNOT statically enumerate is OPAQUE:
# we emit __OPAQUE_BASH__ and let the guard fail CLOSED under an active focus (an
# out-of-scope sentinel never matches scope.paths). This defeats the fail-open bypass
# (dd of=, interpreter -c/-e, eval, $(...), xargs, find -exec, ln, redirect-to-var).
def bash_opaque(c):
    pats=[r"\$\(", r"`", r"<\(", r">\(", r"<<",
          r"\beval\b", r"\b(?:ba)?sh\s+-c\b",
          r"\b(?:python3?|perl|ruby|node)\b[^|;&]*-[A-Za-z]*[ce]\b",
          r"\bawk\b", r"\bxargs\b", r"\bfind\b[^|;&]*-exec\b",
          r"\bdd\b", r"\bln\b", r">\s*\$"]
    return any(re.search(p, c) for p in pats)
def bash_targets(c):
    t=[]
    # `>>?\|?` matches >, >>, and the clobber forms >| / >>| (and fd-prefixed 1>| etc.).
    for m in re.finditer(r"(\d*)>>?\|?\s*(&?)([^\s;|&<>]+)", c):
        fd,amp,tgt=m.groups()
        if amp or tgt.isdigit(): continue
        if tgt in ("/dev/null","/dev/stderr","/dev/stdout"): continue
        t.append(tgt)
    for m in re.finditer(r"(?:^|[;|&])\s*(?:tee|cp|mv|install|truncate|touch|rsync)\b([^;|&]*)", c):
        for tok in m.group(1).split():
            if tok.startswith("-") or "=" in tok: continue
            t.append(tok)
    m=re.search(r"\bsed\b[^;|]*\s-i\S*\s+(?:-e\s+\S+\s+)*([^\s;|&]+)", c)
    if m: t.append(m.group(1))
    return t
def has_redirect(c):
    # any output-redirection operator present (>, >>, >|, N>, &>) — used for the
    # fail-closed backstop: a redirect present but no target resolved is OPAQUE.
    return re.search(r"(?<![0-9<])>|&>", c) is not None
try:
    d=json.loads(sys.stdin.read())
    if not isinstance(d,dict): raise ValueError
    tn=str(d.get("tool_name") or "_")
    ti=d.get("tool_input")
    if not isinstance(ti,dict): raise ValueError
    if any(c in tn for c in "\n\r"): raise ValueError
    paths=[]
    if tn=="Bash":
        cmd=str(ti.get("command") or "")
        if bash_opaque(cmd):
            paths=["__OPAQUE_BASH__"]
        else:
            paths=bash_targets(cmd)
            # fail-closed backstop: a redirect operator is present but resolved to no
            # target (exotic/fd-juggled redirect) — treat as opaque, do not allow.
            if not paths and has_redirect(cmd):
                paths=["__OPAQUE_BASH__"]
    else:
        fp=str(ti.get("file_path") or ti.get("path") or "")
        if fp: paths=[fp]
    print(tn)
    for p in paths:
        if not any(c in p for c in "\n\r"): print(p)
except Exception:
    print("__PARSE_ERROR__")')"

tool="$(printf '%s\n' "$parsed" | sed -n '1p')"
paths="$(printf '%s\n' "$parsed" | sed -n '2,$p')"

if [ "$tool" = "__PARSE_ERROR__" ]; then
  decision="$(scope_guard_decision __PARSE_ERROR__ _)" && exit 0
  echo "[sift scope-guard] $decision" >&2; exit 2
fi

case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit|Bash) ;;
  *) exit 0 ;;                        # non-write tool → allow
esac
[ -n "$paths" ] || exit 0            # write tool but no file target (read-only Bash) → allow

while IFS= read -r p; do
  [ -n "$p" ] || continue
  decision="$(scope_guard_decision Write "$p")" || { echo "[sift scope-guard] $decision" >&2; exit 2; }
done <<EOF
$paths
EOF
exit 0
