## Why

The fork is developed on Windows 11, but the `markitdown` test suite only passes on Linux: with `GITHUB_ACTIONS=1`
(network tests skipped) 41 of 212 tests fail locally, so there is no safety net for the PDF work planned next.
Making the suite trustworthy also exposed two real CLI defects on Windows that the current tests cannot see, both of
which silently corrupt or lose the Markdown this fork exists to produce:

1. **Redirected output is not UTF-8.** `markitdown file.pdf > doc.md` writes the console code page (cp1252) with
   `errors="replace"`: accented text is not valid UTF-8 and anything outside cp1252 (CJK, `→`, `✓`, most math symbols)
   becomes `?`. `-o doc.md` is correct.
2. **Piped stdin is broken.** `cat file.pdf | markitdown` produces empty output with exit code 0 for text formats and a
   conversion error for binary formats (0 of 12 test vectors convert). `markitdown < file.pdf` works. The existing
   test `test_input_from_stdin_without_hints` passes the filename *as well as* stdin, so it never exercised stdin.

## What Changes

- **Tests — interpreter:** CLI tests launch the CLI with `sys.executable` instead of the bare `"python"` command, so the
  subprocess always uses the interpreter (and virtual environment) that runs pytest.
- **Tests — encoding:** CLI tests read output files and captured stdout as UTF-8 explicitly instead of relying on the
  platform locale.
- **Tests — stdin:** `test_input_from_stdin_without_hints` stops passing the filename, so it really converts from stdin.
- **Tests — file URIs:** `test_file_uris` compares against the platform's absolute path; a Windows-only test covers
  drive-letter URIs.
- **CLI fix — stdout:** when stdout is not an interactive terminal (redirected or piped) the converted Markdown is
  written as UTF-8. An explicit `PYTHONIOENCODING` is honored. Interactive terminals keep today's behavior.
- **CLI fix — stdin:** the CLI reads stdin fully into memory before converting, so piped input works on Windows.
- **New tests** for both CLI fixes: platform-neutral in-process tests (they reproduce the Windows defect on any OS) plus
  end-to-end subprocess tests.
- **Docs:** new Windows baseline and CLI guidance in `CLAUDE.md` (`-o` is the only shell-independent way to get UTF-8);
  `PLAN.md` updated.

## Non-goals

- No change to any converter, to `MarkItDown.convert*`, or to conversion output.
- Not making `MarkItDown.convert_stream()` itself robust against Windows pipe objects (library-level fix in
  `_markitdown.py`; the CLI is the only place that hands it a pipe). Recorded as a follow-up.
- Not fixing shells that re-encode a native command's output (Windows PowerShell 5.1 `>`, PowerShell pipelines into
  cmdlets). The CLI cannot control that; `-o` is documented as the reliable option.
- Not fixing tests that need network access, `ffmpeg` (`test_speech_transcription`) or an LLM key; they stay skipped.
- Not silencing the `pydub` "Couldn't find ffmpeg" `RuntimeWarning`, not moving CLI error messages from stdout to stderr.
- Not re-enabling GitHub Actions or adding a Windows CI job (tracked in `PLAN.md`).
- Not touching the other packages' tests. Measured status on Windows: `markitdown-sample-plugin` 2 passed;
  `markitdown-ocr` 35 passed, 1 failed (`test_pdf_multipage`, unrelated to this change); `markitdown-mcp` has no tests.

## Capabilities

### New Capabilities
- `cli-output-encoding`: how the `markitdown` CLI encodes converted Markdown written to stdout (redirected/piped vs.
  interactive terminal, explicit `PYTHONIOENCODING`) and to `-o/--output` files.
- `cli-stdin-input`: converting a document supplied on stdin (pipe or file redirection) on every operating system.
- `cross-platform-test-suite`: the `packages/markitdown` test suite runs green on Windows and stays platform-neutral
  (active interpreter, explicit encodings, platform-aware paths, tests that exercise what they claim).

### Modified Capabilities
<!-- None: openspec/specs/ is empty; no existing spec changes. -->

## Impact

- Code: `packages/markitdown/src/markitdown/__main__.py` (`main`, `_handle_output`, new `_should_force_utf8_stdout`).
- Tests: `packages/markitdown/tests/test_cli_misc.py`, `test_cli_vectors.py`, `test_module_misc.py`.
- Docs: `CLAUDE.md`, `PLAN.md`.
- Expected suite result on Windows (`GITHUB_ACTIONS=1`): from 138 passed / 33 skipped / 41 failed to
  **184 passed / 33 skipped / 0 failed** (measured with a throw-away prototype of this change).
- Output size / tokens: conversion content is unchanged. On Windows, redirected output becomes valid UTF-8 instead of
  lossy cp1252 (same character count, no information lost) and piped input produces output instead of nothing.
- Memory: stdin is now always buffered in memory. POSIX already did this for pipes; only `markitdown < big-file` changes
  (the file is read once into memory instead of being streamed, which most converters did anyway).
- Upstream compatibility: all source changes live in `__main__.py` and are small; both fixes are candidates to propose
  upstream later. Behavior on POSIX with a UTF-8 locale is byte-for-byte unchanged.
