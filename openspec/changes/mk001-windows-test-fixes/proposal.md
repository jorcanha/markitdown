## Why

After syncing the fork with upstream `ed17895` (version `0.1.9`), the `packages/markitdown` suite on Windows reports
1132 passed, 49 skipped and **4 failed** (`GITHUB_ACTIONS=1`, measured). All four failures have one cause, and it is a
real defect, not a test problem: when stdout is redirected or piped, the CLI writes the Markdown in the ANSI code page
(cp1252) with `errors="replace"`. `markitdown file.pdf > doc.md` therefore produces a file that is not valid UTF-8 for
accented text, and every character outside cp1252 (CJK, `→`, `✓`, emoji, most math symbols) becomes `?`. `-o doc.md`
is correct. Upstream does not fix this; its CI hides it by exporting `PYTHONUTF8=1` for every job.

This is the output the fork exists to produce, and data is lost silently, so it is fixed first — which also gives the
fork a fully green suite on Windows before the PDF work starts.

Scope note: the first draft of this change also covered the `"python"` launcher in tests, `test_file_uris`, and piped
stdin on Windows. Upstream had already fixed all three (the fork had been created from a stale clone), so they were
dropped after the sync.

## What Changes

- **CLI fix:** when stdout is not an interactive terminal (redirected or piped), the converted Markdown is written as
  UTF-8. An explicit `PYTHONIOENCODING` is honored. Interactive terminals keep today's behavior.
- **Tests — decoding:** the CLI vector tests that capture stdout decode it as UTF-8 instead of the platform locale.
- **New tests:** platform-neutral in-process tests that reproduce the Windows defect on any OS (fake stdout with a
  legacy encoding, explicit `PYTHONIOENCODING`, fake terminal), plus one end-to-end subprocess test that runs with
  Python's default encoding settings.
- **Linux verification:** the change is executed in a Linux container on a second machine before it is archived, and
  the results are committed to the change folder.
- **Docs:** `CLAUDE.md` baseline and CLI notes (`-o` is the only shell-independent way to get UTF-8); `PLAN.md`;
  `AGENTS.md` pointer so non-Claude agents find the project rules.

## Non-goals

- No change to any converter, to `MarkItDown.convert*`, or to conversion output.
- Not fixing shells that re-encode a native command's output (Windows PowerShell 5.1 `>`, PowerShell pipelines into
  cmdlets or variables). The CLI cannot control that; `-o` is documented as the reliable option.
- Not moving CLI error messages from stdout to stderr (tracked in `PLAN.md`).
- Not fixing tests that need network access, `ffmpeg` or an LLM key; they stay skipped.
- Not re-enabling GitHub Actions. The Linux check is a manual container run, not CI.
- Not proposing the fix upstream (possible later, on the owner's request).

## Capabilities

### New Capabilities
- `cli-output-encoding`: how the `markitdown` CLI encodes converted Markdown written to stdout (redirected/piped vs.
  interactive terminal, explicit `PYTHONIOENCODING`) and to `-o/--output` files.
- `cross-platform-test-suite`: the `packages/markitdown` suite is green on Windows and Linux without relying on
  `PYTHONUTF8`, and encoding defects are covered by tests that fail on any OS.

### Modified Capabilities
<!-- None: openspec/specs/ is empty; no existing spec changes. -->

## Impact

- Code: `packages/markitdown/src/markitdown/__main__.py` (`_handle_output`, new `_should_force_utf8_stdout`).
- Tests: `packages/markitdown/tests/test_cli_misc.py`, `packages/markitdown/tests/test_cli_vectors.py`.
- Docs: `CLAUDE.md`, `PLAN.md`, new `AGENTS.md`; verification script and results inside the change folder.
- Expected suite result on Windows (`GITHUB_ACTIONS=1`): from 1132 passed / 49 skipped / 4 failed to
  **1140 passed / 49 skipped / 0 failed** (measured with a throw-away prototype of this change; also green with
  `PYTHONUTF8=1`, the setting upstream CI uses).
- Output size / tokens: conversion content is unchanged. On Windows, redirected output becomes valid UTF-8 instead of
  lossy cp1252: same number of characters, no information lost. The gain is correctness, not size.
- Upstream compatibility: 15 added lines in `__main__.py`, no upstream line removed. Behavior on POSIX with a UTF-8
  locale is expected to be byte-for-byte unchanged (to be confirmed by the Linux run).
