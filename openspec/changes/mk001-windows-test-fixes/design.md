## Context

Environment used for every measurement below: Windows 11, Python 3.13.13, uv virtual environment, `GITHUB_ACTIONS=1`
(network tests skipped), PowerShell 7.7.0, Windows PowerShell 5.1, cmd.exe and Git Bash. Upstream CI (`ubuntu-latest`,
Python 3.10–3.12) passes with the same code, and it only runs `packages/markitdown`.

Baseline: **138 passed, 33 skipped, 41 failed**.

| # | Symptom | Root cause | Kind |
|---|---|---|---|
| 1 | 40 CLI tests: `No module named markitdown` | `subprocess.run(["python", ...])`. On Windows `CreateProcess` looks for `python.exe` in the directory of the *running* executable first. The venv `python.exe` is a launcher that re-executes the base interpreter, so the base interpreter (which lacks the package) is found — **even with the venv activated**. | Test bug |
| 2 | `test_output_to_file`, `test_output_to_file_with_data_uris`: `UnicodeDecodeError: 'charmap'` | Test reads the UTF-8 output file with `open(path, "r")` → cp1252 on Windows. | Test bug |
| 3 | `test_output_to_stdout` (`test_mskanji.csv`): `\| ?? \| ?? \| ?? \|` | `__main__.py::_handle_output` encodes with `sys.stdout.encoding` (cp1252 when stdout is not a console) and `errors="replace"`. | **CLI bug** |
| 4 | `cat file \| markitdown`: empty output + exit 0 (text formats), `BadZipFile` / `PDFKeyError` (binary formats). 0 of 12 vectors convert. | `sys.stdin.buffer.seekable()` returns `True` for a pipe on Windows, so `MarkItDown.convert_stream` (`_markitdown.py:370`) skips its "copy non-seekable stream to `BytesIO`" step. Magika and the converters then seek a stream that cannot be rewound. | **CLI bug**, hidden by #5 |
| 5 | `test_input_from_stdin_without_hints` passes on every OS | It passes the filename **and** `input=`; the CLI converts the file and ignores stdin. | Test bug |
| 6 | `test_module_misc.py::test_file_uris` | `_uri_utils.file_uri_to_path` correctly applies `os.path.abspath` (adds the drive letter on Windows); the test hard-codes POSIX paths. | Test bug |

A throw-away prototype of this design was applied and then reverted. Results:

- Tests updated, CLI **not** fixed (red phase): 20 failed — 12 stdin vectors, 6 stdout vectors, 2 of the new tests.
- Tests updated and CLI fixed: **184 passed, 33 skipped, 0 failed**, running `.venv\Scripts\python -m pytest` without
  activating the venv.

What the stdout fix can and cannot do depends on the shell (measured with a CSV containing `José`, `名前`, `→ ✓ €`):

| Invocation | Today | With D3 |
|---|---|---|
| `markitdown f -o out.md` (any shell) | valid UTF-8 | valid UTF-8 |
| cmd.exe / Git Bash: `> out.md`, `\| other-program` | invalid UTF-8, `?` for non-cp1252 | valid UTF-8, intact |
| PowerShell ≥ 7.4: `> out.md` (byte-preserving redirection) | invalid UTF-8, `?` | valid UTF-8, intact |
| PowerShell 7: `\| Out-File`, `$x = markitdown f` | mojibake | intact **only if** `[Console]::OutputEncoding` is UTF-8 |
| Windows PowerShell 5.1: `> out.md` | UTF-16 file with mojibake (`JosÚ`) | UTF-16 file with different mojibake (`Jos├®`) |

PowerShell decodes a native command's output with `[Console]::OutputEncoding` (OEM code page 850 on this machine) before
it writes or pipes it, so the last two rows are outside the CLI's control. `-o` is the only shell-independent option.

Constraints: CI is disabled in the fork and this machine has neither WSL nor Docker, so nothing can be executed on
Linux as part of this change.

## Goals / Non-Goals

**Goals:**
- 0 failures on Windows for `packages/markitdown/tests` with network tests skipped.
- Redirected/piped CLI output is lossless UTF-8 wherever the shell passes bytes through.
- Documents piped into the CLI convert on Windows exactly as they do from a path.
- Every new behavior is covered by a test that fails before the fix, on any OS where that is possible.

**Non-Goals:**
- No change to converters or to the Python API; no new dependency.
- No library-level fix for `convert_stream` + Windows pipes (see D4 alternatives).
- No fix for re-encoding shells, network/ffmpeg tests, the `pydub` warning, or CI.

## Decisions

### D1 — Launch the CLI with `sys.executable` in tests
`tests/test_cli_misc.py` (`test_version`, `test_invalid_flag`) and `tests/test_cli_vectors.py` (`test_output_to_stdout`,
`test_output_to_file`, `test_input_from_stdin_without_hints`, `test_convert_url`, `test_output_to_file_with_data_uris`)
replace `"python"` with `sys.executable`.
- Alternative: require an activated venv → rejected: proven not to work on Windows (root cause #1).
- Alternative: call the `markitdown` console script → rejected: depends on `Scripts/` being on `PATH`.

### D2 — Explicit UTF-8 in tests
- `subprocess.run(..., text=True)` gains `encoding="utf-8"`.
- `.decode(locale.getpreferredencoding())` becomes `.decode("utf-8")`; the unused `import locale` is removed.
- `open(output_file, "r")` becomes `open(output_file, "r", encoding="utf-8")`.
- On Linux the preferred encoding is already UTF-8, so nothing changes there.

### D3 — CLI writes UTF-8 when stdout is not a terminal
`packages/markitdown/src/markitdown/__main__.py`: new module-level helper `_should_force_utf8_stdout()` and a call in the
stdout branch of `_handle_output` before the existing `print`:

```python
def _should_force_utf8_stdout() -> bool:
    """True when stdout is not a terminal and no encoding was explicitly requested."""
    return (
        not sys.stdout.isatty()
        and not os.environ.get("PYTHONIOENCODING")
        and hasattr(sys.stdout, "reconfigure")
    )
```

```python
        if _should_force_utf8_stdout():
            sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[union-attr]
```

- Not opt-in: it is a bug fix, there is no flag. No Python API change (`MarkItDown` never writes to stdout).
- The existing `encode(sys.stdout.encoding, errors="replace").decode(...)` round trip stays: after `reconfigure` it is
  lossless for normal text and still protects against lone surrogates coming out of a converter.
- `reconfigure` keeps the text layer, so newline handling is unchanged (CRLF on Windows, same as `-o`).
- **Escape hatch:** an explicit `PYTHONIOENCODING` wins. Anyone who depended on a legacy code page can keep it, and the
  fix never overrides a deliberate user setting. `PYTHONUTF8=1` already yields UTF-8, so it needs no special case.
- `hasattr` keeps the CLI working when a host replaced `sys.stdout` with an object without `reconfigure`.
- POSIX with a UTF-8 locale: `sys.stdout.encoding` is already `utf-8`; output bytes are identical.
- Alternative: force UTF-8 on terminals too → rejected: mojibake on POSIX terminals with a non-UTF-8 locale; on Windows
  the console stream is already Unicode-safe.
- Alternative: write bytes to `sys.stdout.buffer` → rejected: bypasses newline translation and the text layer.
- Alternative: only document `PYTHONUTF8=1` → rejected: silently lossy by default is the wrong default for a tool whose
  output feeds an LLM.

### D4 — CLI buffers stdin before converting
`__main__.py::main`, stdin branch: pass `io.BytesIO(sys.stdin.buffer.read())` instead of `sys.stdin.buffer`.
- Fixes root cause #4 for every way of supplying stdin, and is a no-op in effect on POSIX, where `convert_stream`
  already copied the non-seekable pipe into a `BytesIO`.
- Trade-off: `markitdown < big-file` now holds the file in memory. Accepted: `PdfConverter`, `ZipConverter`,
  `DocumentIntelligenceConverter` and others already read the whole stream.
- Alternative: fix `MarkItDown.convert_stream` (`_markitdown.py:370`) with a real seekability probe (e.g.
  `stat.S_ISREG(os.fstat(stream.fileno()).st_mode)`) → rejected for this change: it touches the core module that
  upstream edits most (merge-conflict risk) for a case only the CLI hits. Recorded in `PLAN.md` as a follow-up and as a
  candidate upstream contribution.
- Not opt-in: bug fix, no flag, no Python API change.

### D5 — The stdin test must use stdin
`tests/test_cli_vectors.py::test_input_from_stdin_without_hints` drops the filename argument. This is the same code
path as the in-process `test_module_vectors.py::test_convert_stream_without_hints`, which already passes for every
vector on Linux CI and on Windows, so no vector is expected to regress on any OS.

### D6 — Platform-aware `test_file_uris`
`tests/test_module_misc.py::test_file_uris` compares the five cases against
`os.path.abspath("/path/to/file.txt")` (unchanged on POSIX). New `test_file_uris_windows_drive`, skipped unless
`sys.platform == "win32"`, asserts `file:///C:/path/to/file.txt` → `(None, r"C:\path\to\file.txt")`.
No change to `_uri_utils.py`.

### D7 — Test strategy for the CLI fixes
End-to-end subprocess tests only fail on Windows before the fix, and upstream CI is Linux. So `_handle_output` is also
tested **in process** with a fake stdout, which reproduces the defect on any OS:

- `_FakeStdout(io.TextIOWrapper)` wraps a `BytesIO` with a chosen `encoding` and `isatty()` result.
- `test_redirected_stdout_is_utf8_even_with_legacy_locale`: cp1252, not a TTY → bytes decode as UTF-8, text intact.
- `test_redirected_stdout_honors_pythonioencoding`: `PYTHONIOENCODING=cp1252` → output stays cp1252 (`?` replacements).
- `test_terminal_stdout_replaces_unsupported_characters`: ascii, TTY → `b"Jos? | ?? | ? ?\n"`, no exception.
- `test_cli_redirected_stdout_is_utf8`: subprocess with captured stdout on `test_mskanji.csv`, `PYTHONIOENCODING`
  removed from the child environment.
- stdin end to end: the 12 vectors of `test_input_from_stdin_without_hints` (D5).

`tests/test_cli_misc.py` imports `_handle_output` from `markitdown.__main__`; that module only runs `main()` under
`if __name__ == "__main__"`, so importing it has no side effects.

### D8 — Tooling for this change
- Run tests with the venv interpreter directly: `.venv\Scripts\python -m pytest packages/markitdown/tests -q`
  (activation is not needed once D1 is in).
- Format with the version pinned in `.pre-commit-config.yaml`, on touched files only:
  `uvx black==23.7.0 <files>`. The latest black (26.x) wants to reformat three untouched upstream files, which would
  create noise and future merge conflicts.

### D9 — Linux verification
Nothing can be run on Linux locally and CI is off. The change therefore relies on: (a) tests whose expectations are
computed from the platform (`os.path.abspath`) or are platform-independent (explicit UTF-8, fake stdout); (b) the
analysis in D3/D4/D5 that POSIX behavior is unchanged; (c) a note in `PLAN.md` to run the upstream `tests` workflow on
Linux when CI is re-enabled, before trusting the Linux claim.
- Alternative: temporarily re-enable GitHub Actions for one run → the owner disabled CI on purpose; left as an owner
  decision (see Open Questions).

## Risks / Trade-offs

- [A Windows consumer relied on cp1252 bytes from a redirected stdout] → `PYTHONIOENCODING=cp1252` restores it; the old
  output was lossy anyway. Called out in the commit message.
- [PowerShell users still get mojibake with `>` (5.1) or pipelines] → not fixable in the CLI; documented in `CLAUDE.md`
  with the `-o` recommendation.
- [`isatty()` is False in some IDE consoles that render a legacy code page] → non-ASCII would display as mojibake there;
  such consoles are normally UTF-8 today, and files/pipes are the primary use.
- [Linux behavior is not executed, only reasoned] → D9; first CI run after re-enabling is the confirmation.
- [Importing a private function (`_handle_output`) in tests couples tests to internals] → accepted: it is the only way
  to reproduce the Windows defect on Linux CI.
- [Upstream changes the same tests or `__main__.py`] → small, localized diffs; easy to re-apply on merge.

## Migration Plan

No migration. Rollback = revert the change's commits.

## Open Questions

- Should the owner allow a one-off Linux run (temporarily restoring `.github/workflows/tests.yml` on the feature branch,
  or a `workflow_dispatch` trigger) before merging? Default if unanswered: no; follow D9.
