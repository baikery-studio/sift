#!/usr/bin/env python3
"""Single source of truth for "what file(s) does this Bash command write?" (stdlib only).

Both the ENFORCING PreToolUse scope guard (hooks/pretooluse-scope.sh) and the ADVISORY
PostToolUse detector (hooks/posttool-reset.sh) must agree on which commands write and to
where, or the live fence is porous (the enforcing parser used to recognise a strictly
smaller command set than the advisory one). This module is that shared set, so the two
hooks can never drift again.

write_targets(cmd) -> list of path operands the command writes; ["__OPAQUE_BASH__"] when it
writes but the targets cannot be statically enumerated (the guard then fails CLOSED under an
active focus); [] when read-only.
is_write(cmd) -> bool, derived from write_targets (non-empty => a write).
"""
import re

# Destructive / write-capable commands whose operands are paths, anchored at a command
# position (start, or after ; | & && || or a newline) so `npm install` / names like dd-trace
# don't false-positive. Superset of the redirect + tee/... set plus rm/mkdir/rmdir/chmod/
# chown/tar/unzip. NOTE: `ln` is OPAQUE (its checked operand is the LINK name, not the symlink
# TARGET — a scope-passing link to an out-of-scope target would otherwise slip), and `sed -i`
# is OPAQUE (its in-place target is fragile to parse across GNU/BSD forms): both fail closed.
_TGT_CMDS = (r"tee|cp|mv|install|truncate|touch|rsync|rm|mkdir|rmdir|chmod|chown|tar|unzip")

# A command-position prefix the anchor must skip BEFORE the command name, or it is a bypass:
# env-var assignments (FOO=bar), sudo/command/builtin/exec/env wrappers, and an absolute or
# relative path to the binary (/bin/rm, ./rm). Without this, `FOO=x rm out`, `sudo rm out`,
# `/bin/rm out` all evade the write-command match and the fence allows them.
_PFX = (r"(?:[A-Za-z_]\w*=\S*\s+)*"
        r"(?:(?:sudo|command|builtin|exec|env)\s+(?:[A-Za-z_]\w*=\S*\s+)*)*"
        r"(?:\S*/)?")

# Forms whose write target cannot be statically resolved — fail closed under focus:
# command/process substitution, here-docs, interpreters with inline scripts, eval, awk,
# xargs, find -exec, dd, redirect-to-variable, git tree ops (checkout/restore/clean operate
# on refs/trees), symlink creation (ln), in-place sed, and downloaders (curl -o/-O/--output,
# any wget — writes to cwd by default). These match the keyword ANYWHERE (\b), so an env/sudo/
# path prefix does not evade them.
_OPAQUE = [
    r"\$\(", r"`", r"<\(", r">\(", r"<<",
    r"\beval\b", r"\b(?:ba)?sh\s+-c\b",
    r"\b(?:python3?|perl|ruby|node)\b[^|;&]*-[A-Za-z]*[ce]\b",
    r"\bawk\b", r"\bxargs\b", r"\bfind\b[^|;&]*-exec\b", r"\bdd\b", r">\s*\$",
    r"\bln\b", r"\bsed\b[^|;&]*\s-i",
    r"\bcurl\b[^|;&]*\s-[oO]\b", r"\bcurl\b[^|;&]*--output\b", r"\bwget\b",
    r"\bgit\b[^|;&]*\b(?:checkout|restore|clean)\b",
]


def _opaque(c):
    return any(re.search(p, c) for p in _OPAQUE)


def write_targets(c):
    if _opaque(c):
        return ["__OPAQUE_BASH__"]
    t = []
    # redirections: >, >>, clobber >| / >>|, fd-prefixed (1>|), and the deprecated `>&word`
    # both-streams-to-file form (with or without a space after &). Skip ONLY true fd-dups
    # (a DIGIT target: `>&2`, `>&1`, `>2`) and the benign sinks /dev/null,/dev/stderr,/dev/stdout.
    # A `>&word` with a NON-digit target is a real file write (`echo x >&/tmp/exfil` writes
    # /tmp/exfil) — the old `if amp` skip dropped it, a scope-guard bypass (FENCE-DEVNULL-1).
    for m in re.finditer(r"(\d*)>>?\|?\s*(&?)\s*([^\s;|&<>]+)", c):
        fd, amp, tgt = m.groups()
        if tgt.isdigit():
            continue
        if tgt in ("/dev/null", "/dev/stderr", "/dev/stdout"):
            continue
        t.append(tgt)
    # path operands of write-capable commands (skip flags and k=v options). The anchor skips a
    # command-position prefix (env/sudo/command/path) so a prefixed destructive command is
    # still caught; newlines count as separators too.
    for m in re.finditer(r"(?:^|[;|&\n])\s*%s(?:%s)\b([^;|&\n]*)" % (_PFX, _TGT_CMDS), c):
        for tok in m.group(1).split():
            if tok.startswith("-") or "=" in tok:
                continue
            t.append(tok)
    # A DANGLING redirect — an operator with no following target token (`cmd >`, `cmd >> ;`) —
    # cannot be resolved, so fail closed. This is narrower than "any redirect with an empty
    # target list": a redirect whose target WAS resolved and then intentionally skipped
    # (`> /dev/null`, `2>&1`, `>&2`) is a no-op write, not an unresolvable one, and must stay
    # read-only (FENCE-DEVNULL-1). `>&N` fd-dups are excluded (a stream dup is not a file write);
    # `> $VAR` is already opaque via _OPAQUE. The lookbehind still excludes fd-prefixed forms.
    if not t and re.search(r"(?<![0-9<])>>?\|?\s*(?:[;|\n]|$)", c):
        return ["__OPAQUE_BASH__"]
    return t


def is_write(c):
    return bool(write_targets(c))


if __name__ == "__main__":
    import sys
    mode = sys.argv[1] if len(sys.argv) > 1 else "targets"
    cmd = sys.stdin.read()
    if mode == "iswrite":
        sys.exit(0 if is_write(cmd) else 1)
    for p in write_targets(cmd):
        print(p)
