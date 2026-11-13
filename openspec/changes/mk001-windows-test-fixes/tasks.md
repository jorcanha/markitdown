## 1. Regression test first (TDD)

- [ ] 1.1 Add `test_redirected_stdout_is_utf8` to `packages/markitdown/tests/test_cli_misc.py` (design D5): run `[sys.executable, "-m", "markitdown", <TEST_FILES_DIR>/test_mskanji.csv]` with `capture_output=True` and no `text=True`; assert `returncode == 0`, `stdout.decode("utf-8")` succeeds and contains `| 名前 | 年齢 | 住所 |`. Add `import os`, `import sys` and a `TEST_FILES_DIR` constant (`os.path.join(os.path.dirname(__file__), "test_files")`). Confirm it fails on Windows before task 3.1.

## 2. Test suite fixes

- [ ] 2.1 In `packages/markitdown/tests/test_cli_misc.py`, replace `"python"` with `sys.executable` in `test_version` and `test_invalid_flag`, and add `encoding="utf-8"` to their `subprocess.run` calls (design D1, D2).
- [ ] 2.2 In `packages/markitdown/tests/test_cli_vectors.py`, add `import sys` and replace `"python"` with `sys.executable` in `test_output_to_stdout`, `test_output_to_file`, `test_input_from_stdin_without_hints`, `test_convert_url`, `test_output_to_file_with_data_uris` (design D1).
- [ ] 2.3 In `packages/markitdown/tests/test_cli_vectors.py`, make decoding explicit: `encoding="utf-8"` on every `text=True` `subprocess.run`; `.decode("utf-8")` instead of `locale.getpreferredencoding()` in `test_input_from_stdin_without_hints` and `test_convert_url`; `open(output_file, "r", encoding="utf-8")` in `test_output_to_file` and `test_output_to_file_with_data_uris`; remove the unused `import locale` (design D2).
- [ ] 2.4 In `packages/markitdown/tests/test_module_misc.py::test_file_uris`, compare all five cases against `os.path.abspath("/path/to/file.txt")` (design D4).
- [ ] 2.5 Add `test_file_uris_windows_drive` to `packages/markitdown/tests/test_module_misc.py`, skipped unless `sys.platform == "win32"`, asserting `file_uri_to_path("file:///C:/path/to/file.txt") == (None, r"C:\path\to\file.txt")`; add `import sys` if missing (design D4).

## 3. CLI fix

- [ ] 3.1 In `packages/markitdown/src/markitdown/__main__.py::_handle_output`, in the stdout branch, call `sys.stdout.reconfigure(encoding="utf-8")` when `not sys.stdout.isatty()` and `hasattr(sys.stdout, "reconfigure")`, before the existing `print(...)`; add a short English comment explaining why (design D3). Verify `test_redirected_stdout_is_utf8` now passes.
- [ ] 3.2 Manually verify on Windows with a scratch file (outside the repo) containing `José,Bogotá,→ ✓ €`: `markitdown sample.csv > out.md` yields valid UTF-8 identical to `markitdown sample.csv -o out.md`.

## 4. Documentation

- [ ] 4.1 Update `CLAUDE.md`: replace the "Windows baseline" bullet list with the new result (0 failed), remove the "pending fix" notes, document that redirected CLI output is UTF-8, and add a decision-log entry for mk001.
- [ ] 4.2 Update `PLAN.md`: tick "Make the test suite pass on Windows" with `(mk001)`, and add a follow-up item: `test_input_from_stdin_without_hints` passes the filename too, so it never exercises stdin.

## 5. Verification

- [ ] 5.1 From the activated `.venv`, run `GITHUB_ACTIONS=1 python -m pytest packages/markitdown/tests -q` and confirm 0 failures (spec: Green local baseline on Windows).
- [ ] 5.2 Run `black packages/markitdown` (via `uv run --with black` or `pre-commit run --all-files`) and confirm no diff remains.
