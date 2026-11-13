## ADDED Requirements

### Requirement: CLI tests use the active interpreter
Tests that launch the `markitdown` CLI as a subprocess SHALL invoke it through the interpreter running the tests
(`sys.executable -m markitdown`) and SHALL NOT rely on a `python` executable resolved from `PATH`.

#### Scenario: Running the suite from a Windows virtual environment
- **WHEN** the suite is run with `.venv\Scripts\python -m pytest packages/markitdown/tests` on Windows, where `python` on `PATH` is the base interpreter without `markitdown` installed
- **THEN** `test_cli_misc.py::test_version` passes and the CLI subprocess finds the `markitdown` package

### Requirement: CLI tests use explicit UTF-8 decoding
Tests that inspect CLI output SHALL read output files and decode captured stdout as UTF-8, and SHALL NOT depend on
the platform's default or locale encoding.

#### Scenario: Reading an output file containing CJK text
- **WHEN** `test_cli_vectors.py::test_output_to_file` runs for `test_mskanji.csv` on Windows
- **THEN** the output file is read as UTF-8 and the assertion on `| 名前 | 年齢 | 住所 |` passes

#### Scenario: Decoding captured stdout
- **WHEN** `test_cli_vectors.py::test_output_to_stdout` runs for `test_mskanji.csv` on Windows
- **THEN** stdout is decoded as UTF-8 and contains `| 名前 | 年齢 | 住所 |`

### Requirement: File URI tests are platform-aware
Tests of `markitdown._uri_utils.file_uri_to_path` SHALL compare against the platform's absolute path for the URI's
path component, and SHALL cover drive-letter URIs on Windows.

#### Scenario: POSIX-style file URI
- **WHEN** `file_uri_to_path("file:///path/to/file.txt")` is called
- **THEN** the returned path equals `os.path.abspath("/path/to/file.txt")` (`/path/to/file.txt` on POSIX, `<current drive>:\path\to\file.txt` on Windows)

#### Scenario: Drive-letter file URI on Windows
- **WHEN** `file_uri_to_path("file:///C:/path/to/file.txt")` is called on Windows
- **THEN** the returned netloc is `None` and the path is `C:\path\to\file.txt`

### Requirement: Green local baseline on Windows
With network tests skipped (`GITHUB_ACTIONS` set), the `packages/markitdown` test suite SHALL pass on Windows 11 with
Python 3.13 and on Linux, with no failures; tests requiring unavailable external tools MAY be skipped.

#### Scenario: Local Windows run
- **WHEN** the owner runs `GITHUB_ACTIONS=1 python -m pytest packages/markitdown/tests -q` from the activated `.venv` on Windows
- **THEN** the run reports 0 failed tests
