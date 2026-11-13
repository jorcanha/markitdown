## Context

All measurements: Windows 11, Python 3.13.13, uv virtual environment, `GITHUB_ACTIONS=1` (network tests skipped),
code at `main` = `af77f03` (upstream `ed17895`, version `0.1.9`). Checked `git fetch upstream` on 2026-11-13: the
defect below is still present on `upstream/main`.

Baseline: **1132 passed, 49 skipped, 4 failed**. The failures:

| Test | Vector | What the test sees |
|---|---|---|
| `test_cli_vectors.py::test_output_to_stdout` | `test_mskanji.csv` | `\| ?? \| ?? \| ?? \|` instead of `\| 名前 \| 年齢 \| 住所 \|` |
| `test_cli_vectors.py::test_output_to_stdout` | `json_late_non_ascii.json` | `caf�, ???, ?` instead of `café, 日本語, 😀` |
| `test_cli_vectors.py::test_input_from_stdin_without_hints` | the same two vectors | the same output |

Root cause (`packages/markitdown/src/markitdown/__main__.py:315-319`):

```python
        encoding = sys.stdout.encoding or "utf-8"
        print(result.markdown.encode(encoding, errors="replace").decode(encoding))
```

When stdout is a pipe or a file, Python on Windows sets `sys.stdout.encoding` to the ANSI code page (cp1252 here), so
the round trip replaces everything outside cp1252 with `?` and writes the rest as cp1252 bytes. Upstream's workflow
sets `PYTHONUTF8: "1"` for all jobs (`.github/workflows-disabled/tests.yml:8`, with the comment "Preserve Unicode in
captured CLI output on Windows"), which masks the defect in its Windows job.

What a fix in the CLI can and cannot achieve depends on the shell. Measured before the sync with a CSV containing
`José`, `名前`, `→ ✓ €`, emulating the fix with `PYTHONIOENCODING=utf-8` (the affected code is unchanged since):

| Invocation | Today | With the fix |
|---|---|---|
| `markitdown f -o out.md` (any shell) | valid UTF-8 | valid UTF-8 |
| cmd.exe / Git Bash: `> out.md`, `\| other-program` | invalid UTF-8, `?` for non-cp1252 | valid UTF-8, intact |
| PowerShell 7.7: `> out.md` (byte-preserving redirection) | invalid UTF-8, `?` | valid UTF-8, intact |
| PowerShell 7: `\| Out-File`, `$x = markitdown f` | mojibake | intact **only if** `[Console]::OutputEncoding` is UTF-8 |
| Windows PowerShell 5.1: `> out.md` | UTF-16 file with mojibake (`JosÚ`) | UTF-16 file with different mojibake (`Jos├®`) |

PowerShell decodes a native command's output with `[Console]::OutputEncoding` (OEM code page 850 on this machine)
before writing or piping it, so the last two rows are outside the CLI's control.

A prototype of this design was applied, measured and reverted:

- Tests updated, CLI not fixed (red phase), `test_cli_misc.py` + `test_cli_vectors.py` only: **28 failed**, 61 passed,
  20 skipped — 13 × `test_output_to_stdout`, 13 × `test_input_from_stdin_without_hints`, and two of the new tests.
- Tests updated and CLI fixed, full suite: **1140 passed, 49 skipped, 0 failed**. The two CLI test files also pass with
  `PYTHONUTF8=1` (89 passed, 20 skipped).
- `uvx black==26.10.1 --check` is clean on the three touched files.

Not verified: anything on Linux. This machine has no WSL or container runtime and CI is disabled. A second machine
with Podman Desktop is available (see D5).

## Goals / Non-Goals

**Goals:**
- Redirected/piped CLI output is lossless UTF-8 wherever the shell passes bytes through.
- 0 failures on Windows for `packages/markitdown/tests` without `PYTHONUTF8`.
- The defect is covered by tests that fail without the fix on any OS.
- The change is executed on Linux before it is merged.

**Non-Goals:**
- No change to converters or to the Python API; no new dependency.
- No fix for re-encoding shells, CLI errors on stdout, network tests, or CI.

## Decisions

### D1 — The CLI writes UTF-8 when stdout is not a terminal
`packages/markitdown/src/markitdown/__main__.py`: new module-level helper `_should_force_utf8_stdout()` and a call at
the top of the stdout branch of `_handle_output`:

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

- **Not opt-in:** it is a bug fix, there is no flag. No Python API change (`MarkItDown` never writes to stdout).
  `os` and `io` are already imported in the module.
- Upstream's two lines (`encoding = sys.stdout.encoding or "utf-8"` and the `print`) stay untouched below the new call:
  after `reconfigure` the round trip is lossless for normal text and still protects against lone surrogates and against
  a stdout whose `encoding` is `None`.
- `reconfigure` keeps the text layer, so newline handling is unchanged (CRLF on Windows, the same as `-o`).
- **Escape hatch:** an explicit `PYTHONIOENCODING` wins, so a deliberate user setting is never overridden and anyone
  who depended on a legacy code page can keep it. `PYTHONUTF8=1` already yields UTF-8 and needs no special case.
- `hasattr` keeps the CLI working when a host replaced `sys.stdout` with an object without `reconfigure`.
- pytest's `capsys` stream (used by upstream's in-process CLI tests) is a UTF-8 `TextIOWrapper`; reconfiguring it to
  UTF-8 is a no-op. The full suite confirms it.
- Alternative: force UTF-8 on terminals too → rejected: mojibake on POSIX terminals with a non-UTF-8 locale; on Windows
  the console stream is already Unicode-safe.
- Alternative: write bytes to `sys.stdout.buffer` → rejected: bypasses newline translation and the text layer, and
  breaks the `capsys`-based tests upstream already has.
- Alternative: tell users to set `PYTHONUTF8=1` (what upstream CI does) → rejected: silently lossy by default is the
  wrong default for a tool whose output feeds an LLM.

### D2 — CLI vector tests decode stdout as UTF-8
`packages/markitdown/tests/test_cli_vectors.py`: `test_output_to_stdout` gains `encoding="utf-8"`;
`test_input_from_stdin_without_hints` and `test_convert_url` decode with `"utf-8"` instead of
`locale.getpreferredencoding()`; the then-unused `import locale` is removed.
- Required by D1: without it the parent would decode the child's UTF-8 output as cp1252 on Windows.
- With `PYTHONUTF8=1` (upstream CI) the preferred encoding is already UTF-8, so the tests behave the same there.

### D3 — In-process tests reproduce the defect on any OS
`packages/markitdown/tests/test_cli_misc.py` gets a `_FakeStdout(io.TextIOWrapper)` helper (a `BytesIO` with a chosen
`encoding` and `isatty()` result) and four tests:

- `test_redirected_stdout_is_utf8_even_with_legacy_locale`: cp1252, not a TTY → bytes decode as UTF-8, text intact.
- `test_redirected_stdout_honors_pythonioencoding`: `PYTHONIOENCODING=cp1252` → output stays cp1252 with `?`.
- `test_terminal_stdout_replaces_unsupported_characters`: ascii, TTY → `b"Jos? | ?? | ? ?\n"`, no exception.
- `test_cli_redirected_stdout_is_utf8_without_python_utf8_mode`: subprocess on `test_mskanji.csv` with
  `PYTHONIOENCODING` and `PYTHONUTF8` removed from the child environment, so it also guards the fix on a CI that
  exports `PYTHONUTF8=1`.

The first test is the important one: a subprocess test passes on Linux with or without the fix (the locale is UTF-8),
so only an in-process test with a legacy-encoded fake stdout protects the fix on Linux CI.
The module already imports `main` from `markitdown.__main__`; importing `_handle_output` next to it has no side effects.

### D4 — Tooling
- Tests: `.venv\Scripts\python -m pytest ...` with `$env:GITHUB_ACTIONS = "1"`; no activation needed.
- Formatting: `uvx black==26.10.1 <touched files>` (the version pinned in `.pre-commit-config.yaml` after the sync).

### D5 — Linux verification on a second machine, before archiving
The owner has another machine with Podman Desktop and a different coding agent. The check must therefore be
self-contained and independent of the host OS and of the agent:

- `openspec/changes/mk001-windows-test-fixes/linux-verify.sh` runs **inside** an official `python:<version>-slim`
  container. The container clones the public repository itself, so there are no host mounts, no line-ending
  differences and no dependency on the host's Python.
- It performs three checks and prints one `RESULT` line for each:
  - **A — suite:** full `packages/markitdown/tests` run on the feature branch; pass criterion: 0 failed.
  - **B — the tests detect the defect on Linux:** temporarily restore `__main__.py` from `origin/main` and run the four
    new tests; expected by analysis: exactly one fails (`test_redirected_stdout_is_utf8_even_with_legacy_locale`).
  - **C — POSIX output unchanged:** convert `test_mskanji.csv` with stdout redirected, once with `main`'s `__main__.py`
    and once with the fixed one; pass criterion: identical SHA-256.
- Run twice: Python 3.12 (upstream CI's Windows/ARM version and middle of its Linux range) and 3.13 (the fork's version).
- `linux-verification.md` holds the step-by-step instructions and the results template. The agent on the second
  machine writes `linux-verification-results.md`, ticks the tasks of group 7 and pushes to the feature branch.
- The second machine **reports only**: it does not modify source or tests. A failed check is recorded and pushed; the
  fix is decided on the development machine.
- Alternative: re-enable GitHub Actions for one run → rejected by the owner (CI stays off for now).
- Alternative: mount the working tree into the container → rejected: host-dependent (CRLF checkouts on Windows hosts,
  SELinux labels on Linux hosts, slow mounts through the Podman machine).
- The script cannot run in a container on the development machine, so its mechanics were dry-run in Git Bash against
  a scratch clone with the prototype applied (only the venv activation path was adapted): PRECONDITION, INSTALL,
  A (`1140 passed, 49 skipped`) and WORKTREE passed; B reported two failing tests and C different hashes, which is
  the correct outcome on Windows, where the defect exists. The Linux expectations for B and C remain analysis.
  The instructions say what to do if a step of the script itself fails.

## Risks / Trade-offs

- [A Windows consumer relied on cp1252 bytes from a redirected stdout] → `PYTHONIOENCODING=cp1252` restores it; the old
  output was lossy anyway. Called out in the commit message.
- [PowerShell users still get mojibake with `>` in 5.1 or with pipelines] → not fixable in the CLI; documented in
  `CLAUDE.md` with the `-o` recommendation.
- [`isatty()` is False in some IDE consoles that render a legacy code page] → non-ASCII would display as mojibake there;
  such consoles are normally UTF-8 today, and files/pipes are the primary use.
- [Linux expectations for checks B and C come from analysis] → that is what the run is for; a mismatch is recorded, not
  hidden, and blocks archiving until understood.
- [Importing a private function (`_handle_output`) in tests] → accepted: it is the only way to reproduce the Windows
  defect on Linux; upstream's tests already import `main` from the same module.
- [Upstream later fixes the same lines differently] → the fork's change is 15 added lines in one function plus one
  helper; easy to drop or re-apply when merging.

## Migration Plan

No migration. Rollback = revert the change's commits. Order of work: implement and verify on Windows (task groups 1–6),
push, run the Linux verification on the second machine (group 7), then archive.

## Open Questions

- None blocking. If check B or C disagrees with the analysis on Linux, decide then whether the spec scenario or the
  implementation is wrong.
