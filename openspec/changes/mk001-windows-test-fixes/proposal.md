## Why

The fork is developed on Windows 11, but the `markitdown` test suite only passes on Linux: with `GITHUB_ACTIONS=1`
(network tests skipped) 41 of 212 tests fail locally, so there is no reliable safety net for the PDF work planned next.
Investigating the failures also uncovered a real Windows CLI bug: when stdout is redirected
(`markitdown file.pdf > doc.md`), the Markdown is written in the console code page (cp1252) with `errors="replace"`,
so accented text is not valid UTF-8 and characters outside cp1252 (CJK, `→`, `✓`, many math symbols) become `?`.
That silently corrupts exactly the output this fork exists to produce.

## What Changes

- CLI tests (`test_cli_misc.py`, `test_cli_vectors.py`) launch the CLI with `sys.executable` instead of the bare
  `"python"` command, so the subprocess uses the same interpreter/venv as pytest on every OS.
- CLI tests read the CLI's output deterministically as UTF-8 (output files opened with `encoding="utf-8"`, stdout
  decoded as UTF-8) instead of relying on the platform's locale encoding.
- `test_module_misc.py::test_file_uris` compares against the platform-correct absolute path
  (`os.path.abspath("/path/to/file.txt")`), which is unchanged on POSIX and includes the drive letter on Windows.
  A Windows-only case for drive-letter URIs (`file:///C:/path/to/file.txt`) is added.
- CLI fix: when stdout is **not** an interactive terminal (piped or redirected), the converted Markdown is written as
  UTF-8 bytes. Output to an interactive terminal keeps the current behavior (encode with the console encoding,
  replacing unsupported characters). On Linux/macOS with a UTF-8 locale the produced bytes are identical to today.
- Document the new Windows test baseline in `CLAUDE.md` and tick the item in `PLAN.md`.

## Non-goals

- No change to any converter or to the Python API (`MarkItDown.convert*`); conversion output is unchanged.
- Not fixing tests that require network access, `ffmpeg` (`test_speech_transcription`) or other external tools;
  they stay skipped/environment-dependent.
- Not silencing the `pydub` "Couldn't find ffmpeg" `RuntimeWarning` printed on CLI start-up (separate change).
- Not re-enabling GitHub Actions or adding a Windows CI job (tracked in `PLAN.md`).
- Not touching tests of the other packages (`markitdown-mcp`, `markitdown-ocr`, `markitdown-sample-plugin`);
  none of them invoke a bare `"python"`.

## Capabilities

### New Capabilities
- `cli-output-encoding`: how the `markitdown` CLI encodes converted Markdown written to stdout (redirected/piped vs.
  interactive terminal) and to `-o/--output` files.
- `cross-platform-test-suite`: the requirement that the `markitdown` package test suite runs green on both Windows and
  POSIX, using the active interpreter and explicit encodings.

### Modified Capabilities
<!-- None: openspec/specs/ is empty; no existing spec changes. -->

## Impact

- Code: `packages/markitdown/src/markitdown/__main__.py` (`_handle_output`).
- Tests: `packages/markitdown/tests/test_cli_misc.py`, `packages/markitdown/tests/test_cli_vectors.py`,
  `packages/markitdown/tests/test_module_misc.py`.
- Docs: `CLAUDE.md`, `PLAN.md`.
- Output size / tokens: no change in content. On Windows, redirected output becomes valid UTF-8 instead of lossy
  cp1252; the number of characters stays the same and no information is lost.
- Upstream compatibility: the CLI fix is small and self-contained in `_handle_output`, and is a good candidate to
  propose upstream later. Behavior on POSIX is unchanged.
