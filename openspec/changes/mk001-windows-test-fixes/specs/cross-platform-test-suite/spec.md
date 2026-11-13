## ADDED Requirements

### Requirement: CLI tests decode captured stdout as UTF-8
Tests that capture the CLI's stdout SHALL decode it as UTF-8 and SHALL NOT depend on the platform's locale encoding or on `PYTHONUTF8` being set.

#### Scenario: Captured stdout with CJK text on Windows
- **WHEN** `test_cli_vectors.py::test_output_to_stdout` runs for `test_mskanji.csv` on Windows without `PYTHONUTF8`
- **THEN** stdout is decoded as UTF-8 and the assertion on `| 名前 | 年齢 | 住所 |` passes

#### Scenario: Stdin round trip with late non-ASCII text
- **WHEN** `test_cli_vectors.py::test_input_from_stdin_without_hints` runs for `json_late_non_ascii.json` on Windows without `PYTHONUTF8`
- **THEN** the decoded stdout contains `"notes": "Late Unicode: café, 日本語, 😀"`

### Requirement: Encoding defects are reproducible on any operating system
Each CLI output-encoding behavior fixed for Windows SHALL have at least one test that fails without the fix on every supported operating system, so that a Linux-only run still protects it.

#### Scenario: Legacy stdout encoding simulated in process
- **WHEN** `test_cli_misc.py::test_redirected_stdout_is_utf8_even_with_legacy_locale` runs on Linux against `__main__.py` without the stdout fix
- **THEN** the test fails because the fake cp1252 stdout received bytes that are not the UTF-8 encoding of the Markdown

#### Scenario: End-to-end test ignores the CI's UTF-8 mode
- **WHEN** `test_cli_misc.py::test_cli_redirected_stdout_is_utf8_without_python_utf8_mode` runs in an environment that exports `PYTHONUTF8=1`
- **THEN** the CLI subprocess is started without `PYTHONUTF8` and `PYTHONIOENCODING`, and its stdout still decodes as UTF-8 with `| 名前 | 年齢 | 住所 |`

### Requirement: Green suite on Windows without UTF-8 mode
The `packages/markitdown` test suite SHALL report zero failures on Windows 11 with Python 3.13 when network tests are skipped (`GITHUB_ACTIONS` set) and `PYTHONUTF8` is not set; tests that need unavailable external tools or credentials MAY be skipped.

#### Scenario: Local Windows run
- **WHEN** the owner runs `$env:GITHUB_ACTIONS = "1"; .venv\Scripts\python -m pytest packages/markitdown/tests -q` on Windows
- **THEN** the run reports `1140 passed, 49 skipped` and 0 failed

### Requirement: Green suite on Linux
The `packages/markitdown` test suite SHALL report zero failures in a Linux container (`python:3.12-slim` and `python:3.13-slim`) when network tests are skipped, and the result of that run SHALL be recorded in the change folder before the change is archived.

#### Scenario: Container run on the second machine
- **WHEN** `linux-verify.sh` runs inside `docker.io/library/python:3.12-slim` for branch `feature/mk001-windows-test-fixes`
- **THEN** it prints `RESULT A: PASS` with a pytest summary line that contains no `failed`, and `linux-verification-results.md` records that line and the commit that was tested
