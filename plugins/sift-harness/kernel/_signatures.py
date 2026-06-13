#!/usr/bin/env python3
"""Static safety-signature scanner (stdlib only).

Two signature families:
  TEST-TAMPERING  — disabled/weakened tests the witness layer (W2 reproduce, W4
                    wiring) cannot see: a quietly skipped test, a commented-out
                    assertion, a CI step set to swallow failures. These are
                    BLOCKING — exit 1 — when found in a test/CI file.
  SECURITY        — write-time risk patterns (hardcoded secret, eval(user-input),
                    innerHTML from a variable). Advisory by default (exit 0 + a
                    stderr note); set SIFT_SIGNATURES_BLOCK_SECURITY=1 to block.

File-kind is decided by NAME so a tamper token inside a string in ordinary source
is not a false positive, and string literals are stripped before matching the code
patterns. Missing files are skipped (so callers can pass an optimistic file set).

Usage: _signatures.py <file> [<file> ...]   # exit 1 if a TEST-TAMPERING hit
"""
import os, re, sys

_TEST_NAME = re.compile(
    # test-named files, plus conftest/fixtures/setup helpers that a test imports — a
    # skip decorator in conftest.py has the same effect as one in the test, so it must
    # be scanned too (else it's a gate bypass).
    r'(^|/)(test_[^/]*|[^/]*_test|[^/]*\.test|[^/]*\.spec|conftest|setup_tests?)\.(py|js|ts|jsx|tsx|go|rb|java|cs)$'
    r'|(^|/)[^/]*Tests?\.cs$'
    r'|(^|/)(tests?|fixtures?|__tests__)/')
_STR = re.compile(r'"[^"]*"|\'[^\']*\'')

_TEST_TAMPER = [
    (re.compile(r'\b(it|describe|test)\.skip\b'), 'it/describe/test.skip'),
    (re.compile(r'\bxit\b|\bxdescribe\b'), 'xit/xdescribe'),
    # skip\w* catches skip, skipif, skipped; covers the skipif(True) bypass.
    (re.compile(r'@?pytest\.mark\.(skip\w*|xfail)\b'), 'pytest.mark.skip*/xfail'),
    (re.compile(r'@(unittest\.)?skip\w*\b'), 'unittest skip*/skipIf/skipUnless decorator'),
    (re.compile(r'\bt\.Skip\('), 'go t.Skip()'),
    (re.compile(r'\banswers_for_tests\s*='), 'hardcoded-answer map'),
    # C# xUnit/NUnit/MSTest skip attributes.
    (re.compile(r'\[\s*(Fact|Theory)\s*\(\s*Skip\s*='), 'xUnit [Fact/Theory(Skip=...)]'),
    (re.compile(r'\[\s*Ignore\b'), 'NUnit/MSTest [Ignore]'),
]
# triple-quoted strings span lines -> strip on the whole text (DOTALL) before the
# per-line single/double strip, so a tamper token inside a docstring isn't a false hit.
_TRIPLE = re.compile(r'""".*?"""|\'\'\'.*?\'\'\'', re.S)
# A commented-out assertion: line (#, //) OR C-block (/* expect(...) */) comment.
_COMMENTED_ASSERT = re.compile(r'^\s*(#|//|/\*)\s*(assert\b|expect\s*\()')
# A test-function header (Python/Go/JS-BDD), used to detect an early-return/pass body.
_TESTFN_HEADER = re.compile(r'\bdef\s+test\w*\s*\(|\bfunc\s+Test\w*\s*\(|\b(it|test|describe)\s*\(')
# A bare early return / pass that, as the FIRST body statement, dead-codes the test.
_EARLY_RET = re.compile(r'^\s*(return(\s+(None|nil|null|true|false|[A-Za-z_0-9.]+))?\s*;?|pass)\s*$')
_CI_TAMPER = [
    (re.compile(r'continue-on-error:\s*true'), 'continue-on-error: true'),
    (re.compile(r'if:\s*always\(\)'), 'if: always()'),
]
# NOTE: the strings below are DETECTION regexes (this scanner flags eval()/innerHTML
# in *other* files). This module itself never calls eval/exec — it only matches them.
_SECURITY = [
    (re.compile(r'(password|passwd|secret|api[_-]?key|access[_-]?token|token)\s*=\s*["\'][^"\']{8,}["\']', re.I),
     'hardcoded secret literal'),
    (re.compile(r'\beval\s*\(\s*(req|request|input|params|argv|user)'), 'eval() of user input'),
    (re.compile(r'\.innerHTML\s*=\s*[A-Za-z_$]'), 'innerHTML from a variable'),
]


def _is_test_file(path):
    return bool(_TEST_NAME.search(path))


def _is_ci_file(path, text):
    return path.endswith(('.yml', '.yaml')) and ('jobs:' in text or 'steps:' in text)


def scan(path):
    """Return [(kind, label, line)] for one file ('' if missing/unreadable)."""
    if not os.path.isfile(path):
        return []
    try:
        with open(path, errors='ignore') as fh:
            text = fh.read()
    except OSError:
        return []
    testf = _is_test_file(path)
    cif = _is_ci_file(path, text)
    text = _TRIPLE.sub('', text)               # drop triple-quoted strings (docstrings) first
    hits = []
    lines = text.splitlines()
    in_block = False                            # inside a /* ... */ block comment
    prev_header_idx = None                      # index of the last test-function header seen
    for i, ln in enumerate(lines):
        if testf and _COMMENTED_ASSERT.search(ln):
            hits.append(('TAMPER', 'commented-out assert/expect', ln.strip()))
        # multi-line block comment: an assertion buried inside /* ... */ on its own line
        if testf:
            stripped = ln.strip()
            if in_block:
                if re.search(r'\b(assert\b|expect\s*\()', stripped):
                    hits.append(('TAMPER', 'assert/expect inside a block comment', stripped))
                if '*/' in stripped:
                    in_block = False
            elif stripped.startswith('/*') and '*/' not in stripped:
                in_block = True
        code = _STR.sub('', ln)            # strip string literals before code patterns
        if testf:
            for rx, label in _TEST_TAMPER:
                if rx.search(code):
                    hits.append(('TAMPER', label, ln.strip()))
            # early-return/pass that dead-codes the test body: a bare return/pass as the
            # FIRST body statement right after a test-function header (a conditional return
            # under an `if` is not the first statement, so it is not flagged).
            if _TESTFN_HEADER.search(code):
                prev_header_idx = i
            elif prev_header_idx is not None and code.strip():
                if _EARLY_RET.match(code):
                    hits.append(('TAMPER', 'early return/pass dead-codes test body', ln.strip()))
                prev_header_idx = None   # only the first body statement is checked
        if cif:
            for rx, label in _CI_TAMPER:
                if rx.search(ln):
                    hits.append(('TAMPER', label, ln.strip()))
        for rx, label in _SECURITY:
            if rx.search(code):
                hits.append(('SECURITY', label, ln.strip()))
    return hits


def main(argv):
    block_security = os.environ.get('SIFT_SIGNATURES_BLOCK_SECURITY') == '1'
    tamper = security = False
    for path in argv:
        for kind, label, ln in scan(path):
            sys.stderr.write('%s: %s :: %s :: %s\n' % (kind, label, path, ln))
            if kind == 'TAMPER':
                tamper = True
            else:
                security = True
    if tamper:
        return 1
    if security and block_security:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
