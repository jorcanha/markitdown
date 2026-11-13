#!/usr/bin/env bash
# Linux verification for the OpenSpec change mk001-windows-test-fixes.
#
# Runs INSIDE a python:<version>-slim container, from the root of a fresh clone of the
# feature branch (see linux-verification.md for the podman command). It needs no
# credentials, pushes nothing, and restores every file it touches.
#
# It prints one "RESULT <check>: PASS|FAIL|UNEXPECTED|SKIPPED - <details>" line per check
# and exits 0 only if every check passed.
set -u

MAIN_PY="packages/markitdown/src/markitdown/__main__.py"
TESTS_DIR="packages/markitdown/tests"
NEW_TESTS="test_redirected_stdout_is_utf8_even_with_legacy_locale or test_redirected_stdout_honors_pythonioencoding or test_terminal_stdout_replaces_unsupported_characters or test_cli_redirected_stdout_is_utf8_without_python_utf8_mode"
EXPECTED_B_FAILURE="test_redirected_stdout_is_utf8_even_with_legacy_locale"
STATUS=0

export GITHUB_ACTIONS=1 # skip tests that need the network
unset PYTHONUTF8 PYTHONIOENCODING

echo "== environment"
python --version
uname -sr
echo "LANG=${LANG:-<unset>} LC_ALL=${LC_ALL:-<unset>}"
python -c "import sys, locale; print('stdout encoding:', sys.stdout.encoding, '| preferred encoding:', locale.getpreferredencoding())"
echo "commit: $(git rev-parse HEAD) on $(git rev-parse --abbrev-ref HEAD)"
BASE="$(git merge-base HEAD origin/main)"
echo "base (merge-base with origin/main): $BASE"

echo "== precondition: the CLI fix is on this branch"
if ! grep -q "_should_force_utf8_stdout" "$MAIN_PY"; then
  echo "RESULT PRECONDITION: FAIL - _should_force_utf8_stdout not found in $MAIN_PY; task groups 1-6 are not implemented and pushed yet"
  exit 2
fi
echo "RESULT PRECONDITION: PASS"

echo "== install"
python -m venv /tmp/venv && . /tmp/venv/bin/activate
if ! pip install -q --disable-pip-version-check -e "packages/markitdown[all]" pytest openai pyyaml; then
  echo "RESULT INSTALL: FAIL - pip install failed (see output above)"
  exit 3
fi
echo "RESULT INSTALL: PASS - markitdown $(python -c 'import markitdown; print(markitdown.__version__)')"

echo "== A: full test suite on the feature branch"
python -m pytest "$TESTS_DIR" -q -p no:cacheprovider >/tmp/a.log 2>&1
tail -n 12 /tmp/a.log
A_SUMMARY="$(grep -E '[0-9]+ (passed|failed|error)' /tmp/a.log | tail -n 1)"
if echo "$A_SUMMARY" | grep -q "passed" && ! echo "$A_SUMMARY" | grep -Eq "failed|error"; then
  echo "RESULT A: PASS - $A_SUMMARY"
else
  echo "RESULT A: FAIL - ${A_SUMMARY:-no pytest summary line found}"
  grep -E "^(FAILED|ERROR)" /tmp/a.log
  STATUS=1
fi

echo "== B: the new tests detect the defect when the fix is removed"
cp "$MAIN_PY" /tmp/main_fixed.py
if git show "$BASE:$MAIN_PY" | grep -q "_should_force_utf8_stdout"; then
  echo "RESULT B: SKIPPED - the base commit already contains the fix, nothing to compare against"
else
  git show "$BASE:$MAIN_PY" >"$MAIN_PY"
  python -m pytest "$TESTS_DIR/test_cli_misc.py" -q -p no:cacheprovider -k "$NEW_TESTS" >/tmp/b.log 2>&1
  cp /tmp/main_fixed.py "$MAIN_PY"
  tail -n 8 /tmp/b.log
  B_SUMMARY="$(grep -E '[0-9]+ (passed|failed|error)' /tmp/b.log | tail -n 1)"
  B_FAILED="$(grep -E '^FAILED' /tmp/b.log | sed -E 's/ - .*//; s/.*:://' | sort | tr '\n' ' ' | sed -E 's/ +$//')"
  if [ "$B_FAILED" = "$EXPECTED_B_FAILURE" ]; then
    echo "RESULT B: PASS - without the fix exactly the expected test fails ($B_FAILED) - $B_SUMMARY"
  else
    echo "RESULT B: UNEXPECTED - failed tests without the fix: [${B_FAILED:-none}] - expected: [$EXPECTED_B_FAILURE] - $B_SUMMARY"
    STATUS=1
  fi
fi

echo "== C: redirected output is byte-identical with and without the fix, and valid UTF-8"
C_OK=1
for SAMPLE in test_mskanji.csv json_late_non_ascii.json; do
  python -m markitdown "$TESTS_DIR/test_files/$SAMPLE" >"/tmp/fixed_$SAMPLE.md" 2>/dev/null
  git show "$BASE:$MAIN_PY" >"$MAIN_PY"
  python -m markitdown "$TESTS_DIR/test_files/$SAMPLE" >"/tmp/base_$SAMPLE.md" 2>/dev/null
  cp /tmp/main_fixed.py "$MAIN_PY"
  H_FIXED="$(sha256sum <"/tmp/fixed_$SAMPLE.md" | cut -d' ' -f1)"
  H_BASE="$(sha256sum <"/tmp/base_$SAMPLE.md" | cut -d' ' -f1)"
  UTF8="$(python -c "
import sys
data = open(sys.argv[1], 'rb').read()
try:
    text = data.decode('utf-8')
    print('valid-utf8' if len(text) > 0 and '?' * 2 not in text else 'suspicious-content')
except UnicodeDecodeError:
    print('invalid-utf8')
" "/tmp/fixed_$SAMPLE.md")"
  echo "$SAMPLE: fixed=$H_FIXED base=$H_BASE $UTF8 ($(wc -c <"/tmp/fixed_$SAMPLE.md") bytes)"
  if [ "$H_FIXED" != "$H_BASE" ] || [ "$UTF8" != "valid-utf8" ]; then
    C_OK=0
  fi
done
if [ "$C_OK" = "1" ]; then
  echo "RESULT C: PASS - output identical to the base commit and valid UTF-8 for both samples"
else
  echo "RESULT C: UNEXPECTED - see the per-sample lines above"
  STATUS=1
fi

echo "== worktree"
if [ -z "$(git status --porcelain)" ]; then
  echo "RESULT WORKTREE: PASS - clean, every touched file was restored"
else
  echo "RESULT WORKTREE: FAIL - files left modified:"
  git status --short
  STATUS=1
fi

echo "== done (exit status $STATUS)"
exit "$STATUS"
