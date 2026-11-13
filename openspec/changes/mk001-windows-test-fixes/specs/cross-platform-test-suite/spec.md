## ADDED Requirements

### Requirement: CLI tests use the active interpreter
Tests that launch the `markitdown` CLI as a subprocess SHALL invoke it through the interpreter running the tests (`sys.executable -m markitdown`) and SHALL NOT rely on a `python` executable resolved from `PATH`.

#### Scenario: Running the suite from a Windows virtual environment without activating it
- **WHEN** the suite is run with `.venv\Scripts\python -m pytest packages/markitdown/tests` on Windows, where `python` on `PATH` is the base interpreter without `markitdown` installed
- **THEN** `test_cli_misc.py::test_version` passes and no test fails with `No module named markitdown`

### Requirement: CLI tests use explicit UTF-8 decoding
Tests that inspect CLI output SHALL read output files and decode captured stdout as UTF-8 and SHALL NOT depend on the platform's default or locale encoding.

#### Scenario: Reading an output file containing CJK text
- **WHEN** `test_cli_vectors.py::test_output_to_file` runs for `test_mskanji.csv` on Windows
- **THEN** the output file is read as UTF-8 and the assertion on `| 名前 | 年齢 | 住所 |` passes

#### Scenario: Decoding captured stdout
- **WHEN** `test_cli_vectors.py::test_output_to_stdout` runs for `test_mskanji.csv` on Windows
- **THEN** stdout is decoded as UTF-8 and contains `| 名前 | 年齢 | 住所 |`

### Requirement: Tests exercise the input channel they name
A test that claims to verify conversion from stdin SHALL supply the document only on stdin and SHALL NOT also pass its path as an argument.

#### Scenario: Stdin test without a filename
- **WHEN** `test_cli_vectors.py::test_input_from_stdin_without_hints` runs for `test.pdf`
- **THEN** the CLI is started as `[sys.executable, "-m", "markitdown"]` with the file's bytes as `input` and no other argument

### Requirement: File URI tests are platform-aware
Tests of `markitdown._uri_utils.file_uri_to_path` SHALL compare against the platform's absolute path for the URI's path component and SHALL cover drive-letter URIs on Windows.

#### Scenario: POSIX-style file URI
- **WHEN** `file_uri_to_path("file:///path/to/file.txt")` is called
- **THEN** the returned path equals `os.path.abspath("/path/to/file.txt")` (`/path/to/file.txt` on POSIX, `<current drive>:\path\to\file.txt` on Windows)

#### Scenario: Drive-letter file URI on Windows
- **WHEN** `file_uri_to_path("file:///C:/path/to/file.txt")` is called on Windows
- **THEN** the returned netloc is `None` and the path is `C:\path\to\file.txt`

### Requirement: CLI defects are reproducible on any operating system
Each CLI behavior fixed for Windows SHALL have at least one test that fails without the fix on every supported operating system, so that Linux-only CI still protects it.

#### Scenario: Legacy stdout encoding simulated in process
- **WHEN** `test_cli_misc.py::test_redirected_stdout_is_utf8_even_with_legacy_locale` runs on Linux against a CLI without the stdout fix
- **THEN** the test fails because the fake cp1252 stdout received bytes that are not valid UTF-8

### Requirement: Green local baseline on Windows
The `packages/markitdown` test suite SHALL report zero failures on Windows 11 with Python 3.13 when network tests are skipped (`GITHUB_ACTIONS` set); tests that need unavailable external tools or credentials MAY be skipped.

#### Scenario: Local Windows run
- **WHEN** the owner runs `$env:GITHUB_ACTIONS = "1"; .venv\Scripts\python -m pytest packages/markitdown/tests -q` on Windows
- **THEN** the run reports `184 passed, 33 skipped` and 0 failed
