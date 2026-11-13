## Context

Baseline on Windows 11 / Python 3.13 / uv venv with `GITHUB_ACTIONS=1`: 138 passed, 33 skipped, 41 failed. The same
upstream workflows pass on `ubuntu-latest`. A trial run that only swapped `"python"` for `sys.executable` left 7
failures, all caused by encoding:

| Failure | Root cause | Kind |
|---|---|---|
| 40× CLI tests: `No module named markitdown` | `subprocess.run(["python", ...])`: on Windows `CreateProcess` resolves `python` to the base interpreter (the venv `python.exe` is a launcher that spawns it), which lacks the package | Test bug |
| `test_output_to_file`, `test_output_to_file_with_data_uris`: `UnicodeDecodeError: 'charmap'` | Test reads the UTF-8 output file with `open(path, "r")` → cp1252 on Windows | Test bug |
| `test_output_to_stdout` / `test_input_from_stdin_without_hints` (`test_mskanji.csv`): `| ?? | ?? | ?? |` | `__main__.py::_handle_output` encodes stdout with `sys.stdout.encoding` (cp1252 when redirected) using `errors="replace"` | **CLI bug** |
| `test_module_misc.py::test_file_uris` | `_uri_utils.file_uri_to_path` correctly applies `os.path.abspath`, which adds the drive letter on Windows; the test hard-codes POSIX paths | Test bug |

Manual repro of the CLI bug: `markitdown sample.csv > out.md` produced cp1252 bytes for `José` and `?` for `名前`,
`→`, `✓`; `markitdown sample.csv -o out.md` produced correct UTF-8.

## Goals / Non-Goals

**Goals:**
- 0 failures on Windows for `packages/markitdown/tests` with network tests skipped; identical results on Linux.
- Redirected/piped CLI output is lossless UTF-8 on every OS.

**Non-Goals:**
- No change to converters or to the Python API; no new dependency.
- No network/ffmpeg test fixes, no `pydub` warning suppression, no CI changes.

## Decisions

### D1 — Launch the CLI with `sys.executable` in tests
Files: `tests/test_cli_misc.py::test_version`, `::test_invalid_flag`; `tests/test_cli_vectors.py::test_output_to_stdout`,
`::test_output_to_file`, `::test_input_from_stdin_without_hints`, `::test_convert_url`,
`::test_output_to_file_with_data_uris`. Replace `"python"` with `sys.executable` (add `import sys`).
- Alternative: require an activated venv / prepend `.venv\Scripts` to `PATH` → rejected: proven not to work on Windows
  (venv launcher still resolves to the base interpreter) and fragile anywhere.
- Alternative: call the `markitdown` console script → rejected: depends on `Scripts/` being on `PATH` too.

### D2 — Explicit UTF-8 in tests
- `subprocess.run(..., capture_output=True, text=True)` → add `encoding="utf-8"` in `test_output_to_stdout`,
  `test_output_to_file`, `test_output_to_file_with_data_uris`, `test_version`, `test_invalid_flag`.
- `result.stdout.decode(locale.getpreferredencoding())` → `.decode("utf-8")` in `test_input_from_stdin_without_hints`
  and `test_convert_url`; drop the now-unused `import locale`.
- `open(output_file, "r")` → `open(output_file, "r", encoding="utf-8")`.
- On Linux the preferred encoding is already UTF-8, so assertions are unchanged there.

### D3 — CLI writes UTF-8 when stdout is not a TTY
Change `packages/markitdown/src/markitdown/__main__.py::_handle_output` (stdout branch only):

```python
if not sys.stdout.isatty() and hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
```

followed by the existing `print(result.markdown.encode(sys.stdout.encoding, errors="replace").decode(...))`, which
becomes lossless once the encoding is UTF-8.
- Not opt-in: this is a bug fix with no flag. There is no Python API change (`MarkItDown` never writes to stdout).
- On POSIX with a UTF-8 locale `sys.stdout.encoding` is already `utf-8`, so output bytes are identical.
- `reconfigure` keeps the text layer, so newline translation is unchanged (CRLF on Windows, same as `-o` files opened in
  text mode) and `print` semantics stay the same.
- `hasattr` guard keeps working if `sys.stdout` was replaced by an object without `reconfigure` (e.g. `io.StringIO`
  in an embedding host).
- Alternative: always force UTF-8, also on a TTY → rejected: on a POSIX terminal with a non-UTF-8 locale it would print
  mojibake; on Windows the TTY is already UTF-8 via the console API, so there is no gain.
- Alternative: write bytes to `sys.stdout.buffer` → rejected: bypasses newline translation and interleaves badly with
  any prior text-layer writes.
- Alternative: document `PYTHONUTF8=1` → rejected as the only fix: silently lossy by default is the wrong default for an
  LLM-preprocessing tool; kept as a note in `CLAUDE.md`.

### D4 — Platform-aware `test_file_uris`
In `tests/test_module_misc.py::test_file_uris`, compare against `expected = os.path.abspath("/path/to/file.txt")` for
all five existing cases (POSIX value is unchanged). Add a `@pytest.mark.skipif(sys.platform != "win32", ...)` test
`test_file_uris_windows_drive` asserting `file_uri_to_path("file:///C:/path/to/file.txt") == (None, r"C:\path\to\file.txt")`.
No change to `_uri_utils.py`.

### D5 — Regression test for the CLI bug
Add `tests/test_cli_misc.py::test_redirected_stdout_is_utf8`: run `[sys.executable, "-m", "markitdown", <test_mskanji.csv>]`
with `capture_output=True` (a pipe → not a TTY) and **without** `text=True`; assert `returncode == 0`, that
`stdout.decode("utf-8")` succeeds, and that it contains `| 名前 | 年齢 | 住所 |`. Runs on every OS; on Windows it fails
before D3 and passes after.

## Risks / Trade-offs

- [A consumer on Windows relied on cp1252 bytes when redirecting] → Unlikely and the old output was lossy; UTF-8 is what
  editors, Claude and `-o` already use. Called out in the commit message.
- [`isatty()` is False for some IDE consoles that display cp1252] → They would show mojibake for non-ASCII. Acceptable:
  such consoles are typically UTF-8 aware today, and the file/pipe case is the primary use.
- [Upstream changes the same tests/function] → Small, localized diffs; easy to re-apply when merging upstream.

## Migration Plan

No migration. Rollback = revert the change's commits.

## Open Questions

- `test_cli_vectors.py::test_input_from_stdin_without_hints` passes both `input=` **and** the filename argument, so it never
  exercises stdin. Out of scope here (fixing it may surface new failures); recorded in `PLAN.md` for a follow-up change.
