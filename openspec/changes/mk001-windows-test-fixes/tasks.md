<!--
Line numbers refer to main = af77f03 (upstream ed17895, 0.1.9). If a file moved, locate the edit by the quoted code.
Paths are relative to the repository root. Commands are PowerShell unless stated otherwise.
Prototype (applied, measured, reverted): tests only -> 28 failed / 61 passed / 20 skipped in the two CLI test files;
tests + fix -> full suite 1140 passed / 49 skipped / 0 failed; black 26.10.1 clean on the three touched files.
linux-verify.sh was dry-run in Git Bash against a scratch clone with the prototype applied (mechanics OK).
-->

## 1. Preparation

- [x] 1.1 `git fetch upstream` and confirm `packages/markitdown/src/markitdown/__main__.py` on `upstream/main` still has
      `encoding = sys.stdout.encoding or "utf-8"` with no `reconfigure` (the defect is not fixed upstream).
- [x] 1.2 Baseline: `$env:GITHUB_ACTIONS = "1"; .venv\Scripts\python -m pytest packages/markitdown/tests -q -p no:cacheprovider`
      → expected `4 failed, 1132 passed, 49 skipped`.

## 2. Tests first (red phase)

- [x] 2.1 `packages/markitdown/tests/test_cli_vectors.py:6` — delete the line `import locale`.
- [x] 2.2 `packages/markitdown/tests/test_cli_vectors.py:55-56` (`test_output_to_stdout`) — after `text=True,` add the
      line `encoding="utf-8",` (design D2).
- [x] 2.3 `packages/markitdown/tests/test_cli_vectors.py:118` and `:150` — replace
      `result.stdout.decode(locale.getpreferredencoding()).replace("\r\n", "\n")` with
      `result.stdout.decode("utf-8").replace("\r\n", "\n")` (design D2).
- [x] 2.4 `packages/markitdown/tests/test_cli_misc.py:3` — add `import argparse` above `import io`; `:12-13` — change the
      imports to:

      ```python
      from markitdown import __version__, DocumentConverterResult
      from markitdown.__main__ import main, _handle_output
      ```

- [x] 2.5 `packages/markitdown/tests/test_cli_misc.py` — insert after `test_windows_pipe_input_is_buffered_before_conversion`
      (after line 81, before the comment `# Service flags and endpoints` at line 84) (design D3):

      ```python
      # Encoding of Markdown written to stdout

      TEST_FILES_DIR = os.path.join(os.path.dirname(__file__), "test_files")

      # Accents (representable in cp1252) plus CJK and symbols (not representable).
      NON_ASCII_MARKDOWN = "José | 名前 | → ✓"


      class _FakeStdout(io.TextIOWrapper):
          """An in-memory stdout with a chosen encoding and TTY status."""

          def __init__(self, *, encoding: str, tty: bool) -> None:
              super().__init__(io.BytesIO(), encoding=encoding, newline="\n")
              self._tty = tty

          def isatty(self) -> bool:
              return self._tty

          def written_bytes(self) -> bytes:
              self.flush()
              return self.buffer.getvalue()  # type: ignore[attr-defined]


      def _print_to_fake_stdout(monkeypatch, fake: _FakeStdout) -> bytes:
          monkeypatch.setattr(sys, "stdout", fake)
          _handle_output(
              argparse.Namespace(output=None),
              DocumentConverterResult(markdown=NON_ASCII_MARKDOWN),
          )
          return fake.written_bytes()


      def test_redirected_stdout_is_utf8_even_with_legacy_locale(monkeypatch) -> None:
          # Simulates Windows, where a redirected stdout defaults to cp1252.
          monkeypatch.delenv("PYTHONIOENCODING", raising=False)
          fake = _FakeStdout(encoding="cp1252", tty=False)
          written = _print_to_fake_stdout(monkeypatch, fake)
          assert written.decode("utf-8") == NON_ASCII_MARKDOWN + "\n"


      def test_redirected_stdout_honors_pythonioencoding(monkeypatch) -> None:
          monkeypatch.setenv("PYTHONIOENCODING", "cp1252")
          fake = _FakeStdout(encoding="cp1252", tty=False)
          written = _print_to_fake_stdout(monkeypatch, fake)
          assert written == "José | ?? | ? ?\n".encode("cp1252")


      def test_terminal_stdout_replaces_unsupported_characters(monkeypatch) -> None:
          monkeypatch.delenv("PYTHONIOENCODING", raising=False)
          fake = _FakeStdout(encoding="ascii", tty=True)
          written = _print_to_fake_stdout(monkeypatch, fake)
          assert written == b"Jos? | ?? | ? ?\n"


      def test_cli_redirected_stdout_is_utf8_without_python_utf8_mode() -> None:
          """End to end: a captured (non-TTY) stdout is UTF-8 with Python's defaults."""
          env = {
              k: v
              for k, v in os.environ.items()
              if k not in ("PYTHONIOENCODING", "PYTHONUTF8")
          }
          result = subprocess.run(
              [
                  sys.executable,
                  "-m",
                  "markitdown",
                  os.path.join(TEST_FILES_DIR, "test_mskanji.csv"),
              ],
              capture_output=True,
              env=env,
          )

          assert result.returncode == 0, f"CLI exited with error: {result.stderr!r}"
          assert "| 名前 | 年齢 | 住所 |" in result.stdout.decode("utf-8")


      ```

- [x] 2.6 Red phase: `$env:GITHUB_ACTIONS = "1"; .venv\Scripts\python -m pytest packages/markitdown/tests/test_cli_misc.py packages/markitdown/tests/test_cli_vectors.py -q -p no:cacheprovider`
      → expected `28 failed, 61 passed, 20 skipped`: 13 × `test_output_to_stdout`, 13 × `test_input_from_stdin_without_hints`,
      `test_redirected_stdout_is_utf8_even_with_legacy_locale`, `test_cli_redirected_stdout_is_utf8_without_python_utf8_mode`.
- [x] 2.7 Commit `test(mk001-windows-test-fixes): decode CLI stdout as UTF-8 and cover stdout encoding` (body: red until
      the next commit) and push.

## 3. CLI fix (green phase)

- [x] 3.1 `packages/markitdown/src/markitdown/__main__.py:315-319` (`_handle_output`, stdout branch) (design D1).

      Before:

      ```python
          else:
              # Handle stdout encoding errors more gracefully, with fallback for
              # cases where sys.stdout.encoding is None (e.g. redirected streams).
              encoding = sys.stdout.encoding or "utf-8"
              print(result.markdown.encode(encoding, errors="replace").decode(encoding))
      ```

      After:

      ```python
          else:
              # A redirected or piped stdout uses the locale encoding (e.g. cp1252 on
              # Windows), which silently destroys text outside that code page. Emit
              # UTF-8 instead, unless the user explicitly asked for another encoding.
              if _should_force_utf8_stdout():
                  sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[union-attr]

              # Handle stdout encoding errors more gracefully, with fallback for
              # cases where sys.stdout.encoding is None (e.g. redirected streams).
              encoding = sys.stdout.encoding or "utf-8"
              print(result.markdown.encode(encoding, errors="replace").decode(encoding))
      ```

- [x] 3.2 `packages/markitdown/src/markitdown/__main__.py` — add before `def _exit_with_error` (line 322), two blank lines
      above and below. `os` is already imported (line 5).

      ```python
      def _should_force_utf8_stdout() -> bool:
          """True when stdout is not a terminal and no encoding was explicitly requested."""
          return (
              not sys.stdout.isatty()
              and not os.environ.get("PYTHONIOENCODING")
              and hasattr(sys.stdout, "reconfigure")
          )
      ```

      **REOPENED by the review of 2026-11-13 (adjustment R1, low severity).** The code above was implemented verbatim
      (commit `172c6d3`), but it is a regression against `main` for a replaced `sys.stdout`: `isatty()` is called before
      the `hasattr` guard, so an object that has `encoding` and `write` but no `isatty` now raises
      `AttributeError: ... has no attribute 'isatty'`. On `main` the same object works. Design D1 states the opposite
      intent ("`hasattr` keeps the CLI working when a host replaced `sys.stdout`"). Measured with a prototype (applied,
      run, reverted): the test in step (b) **passes on `main`'s `__main__.py`, fails on `172c6d3`, passes after (a)**.

      (a) `packages/markitdown/src/markitdown/__main__.py:331-333` — put the `hasattr` check first. Anything that has
          `reconfigure` is a `TextIOWrapper`, which always has `isatty`.

          Before:

          ```python
                  not sys.stdout.isatty()
                  and not os.environ.get("PYTHONIOENCODING")
                  and hasattr(sys.stdout, "reconfigure")
          ```

          After:

          ```python
                  hasattr(sys.stdout, "reconfigure")
                  and not sys.stdout.isatty()
                  and not os.environ.get("PYTHONIOENCODING")
          ```

      (b) `packages/markitdown/tests/test_cli_misc.py` — insert after `test_terminal_stdout_replaces_unsupported_characters`
          (after line 136, before `def test_cli_redirected_stdout_is_utf8_without_python_utf8_mode` at line 139), two
          blank lines above and below:

          ```python
          def test_replaced_stdout_without_isatty_is_still_written(monkeypatch) -> None:
              # A host may replace sys.stdout with a minimal object (no isatty, no reconfigure).
              class MinimalStdout:
                  encoding = "utf-8"

                  def __init__(self) -> None:
                      self.parts: list[str] = []

                  def write(self, text: str) -> int:
                      self.parts.append(text)
                      return len(text)

              monkeypatch.delenv("PYTHONIOENCODING", raising=False)
              fake = MinimalStdout()
              monkeypatch.setattr(sys, "stdout", fake)
              _handle_output(
                  argparse.Namespace(output=None),
                  DocumentConverterResult(markdown=NON_ASCII_MARKDOWN),
              )
              assert "".join(fake.parts) == NON_ASCII_MARKDOWN + "\n"
          ```

      (c) Run with `PYTHONIOENCODING` removed (see R2 in task 5.1):
          `Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue; $env:GITHUB_ACTIONS = "1"; .venv\Scripts\python -m pytest packages/markitdown/tests/test_cli_misc.py packages/markitdown/tests/test_cli_vectors.py -q -p no:cacheprovider`
          → measured with the prototype: `90 passed, 20 skipped`. Then the full suite
          (`... -m pytest packages/markitdown/tests -q -p no:cacheprovider`) → expected `1141 passed, 49 skipped`
          (1140 measured today + the new test; the full run with the prototype was not done).
      (d) The suite count changes from 1140 to 1141. Update it where it is a requirement or an expectation:
          `specs/cross-platform-test-suite/spec.md:30` (`1140 passed, 49 skipped` → `1141 passed, 49 skipped`),
          `proposal.md:57` (`**1140 passed / 49 skipped / 0 failed**` → `1141`, and say the extra test came from the
          review), `CLAUDE.md:109` (done together with R2 in task 5.1). Leave the historical measurements as they are
          (`design.md:45`, `design.md:152`, `linux-verification.md:68`, the comment at the top of this file).
      (e) `design.md` D1 — reorder the three conditions in the code block (lines 74-76) as in (a) and extend the
          `hasattr` bullet (line 93): "checked first, so an object without `isatty` is never asked for it". D3 (line 112):
          "four tests" → "five tests", and add `test_replaced_stdout_without_isatty_is_still_written` to the list.
          `linux-verify.sh` needs **no** change: check B selects its four tests by name (`NEW_TESTS`), and the new test
          is not one of them (it passes on the base commit, which has no fix at all, so it cannot be used to detect it).
      (f) `uvx black==26.10.1 --check` on the two files and
          `uvx mypy --python-executable ../../.venv/Scripts/python.exe --ignore-missing-imports --follow-imports=silent --warn-unused-ignores src/markitdown/__main__.py tests/test_cli_misc.py`
          from `packages/markitdown` → both clean with the prototype.
      (g) Commit `fix(mk001-windows-test-fixes): keep a replaced stdout without isatty working` (code, test and the
          artifact updates of (d) and (e)) and push. Then tick this task.

      **R1 applied on 2026-11-13.** Steps (a)–(g) done as written. Measured afterwards, with `PYTHONIOENCODING` and
      `PYTHONUTF8` unset: full suite `1141 passed, 49 skipped`, 0 failed; black 26.10.1 and mypy clean; redirect and
      pipe in Git Bash still valid UTF-8 and equal to `-o` for both sample files.

- [x] 3.3 Green phase: `$env:GITHUB_ACTIONS = "1"; .venv\Scripts\python -m pytest packages/markitdown/tests -q -p no:cacheprovider`
      → expected `1140 passed, 49 skipped`, no `failed`.
- [x] 3.4 Commit `fix(mk001-windows-test-fixes): write UTF-8 when stdout is redirected or piped` (body: output changes from
      the ANSI code page to UTF-8 on Windows; `PYTHONIOENCODING` restores a legacy encoding) and push.

## 4. Manual verification (PowerShell 7)

- [x] 4.1 Redirect and `-o` give the same UTF-8 text:

      ```powershell
      $t = Join-Path $env:TEMP "mk001"; New-Item -ItemType Directory -Force $t | Out-Null
      "name,city,note`nJosé,Bogotá,→ ✓ €`n名前,東京,x" | Set-Content "$t\sample.csv" -Encoding utf8
      .venv\Scripts\markitdown.exe "$t\sample.csv" > "$t\redirect.md"
      .venv\Scripts\markitdown.exe "$t\sample.csv" -o "$t\file.md"
      (Get-Content "$t\redirect.md" -Raw -Encoding utf8).TrimEnd() -eq (Get-Content "$t\file.md" -Raw -Encoding utf8).TrimEnd()
      Select-String -Path "$t\redirect.md" -Pattern "名前" -Encoding utf8 -Quiet
      Remove-Item -Recurse $t
      ```

      Expected: `True` and `True`.

      Review of 2026-11-13: confirmed, and extended to the other shells named in the spec scenario "Redirecting to a
      file from a byte-preserving shell on Windows", with `PYTHONIOENCODING` and `PYTHONUTF8` unset, for
      `test_mskanji.csv` and `json_late_non_ascii.json`: Git Bash `>` and `| cat >`, cmd.exe `>` and `| findstr >`,
      PowerShell 7.7 `>` — every output is valid UTF-8 and equal to the `-o` file (which lacks only `print`'s final
      newline). `PYTHONIOENCODING=cp1252` gives the legacy lossy output, as specified.

## 5. Documentation

- [ ] 5.1 `CLAUDE.md:108-112` — replace the whole "Windows baseline" bullet (five lines, from
      `- **Windows baseline (2026-11-13, upstream` to `which is always UTF-8.`) with:

      ```markdown
      - **Windows baseline (after `mk001`, upstream `ed17895`, `GITHUB_ACTIONS=1`)**: 1140 passed, 49 skipped, 0 failed —
        without `PYTHONUTF8`. Upstream CI exports `PYTHONUTF8=1`; the fork's suite must stay green without it.
      - **CLI output encoding**: a redirected or piped stdout is UTF-8 (unless `PYTHONIOENCODING` is set, which wins).
        `markitdown <file> -o <out.md>` is UTF-8 in every shell and is the recommended form: Windows PowerShell 5.1 (`>`)
        and PowerShell pipelines into cmdlets or variables re-encode a native command's output and can still corrupt
        non-ASCII text, which the CLI cannot prevent.
      ```

      **REOPENED by the review of 2026-11-13 (adjustment R2, documentation accuracy).** The two bullets above were
      written as specified. The problem is a third bullet that the implementation added right below them
      (`CLAUDE.md:115-117`, commit `620f41e`, not part of this task list), "Agent sessions may export
      `PYTHONIOENCODING` ...". Checked against the branch at `5ddd389`:

      - It says a baseline run "shows 10 failures instead of the real 4" and "Before running the suite:
        `Remove-Item Env:PYTHONIOENCODING`". That is true only for the code **before** this change. On this branch the
        full suite with `PYTHONIOENCODING=utf-8:surrogateescape` left set gives `1140 passed, 49 skipped` (measured),
        the same as without it. The note is stale the moment the change is merged.
      - It misses the consequence that does survive the change: with the variable set, the CLI honors it and skips its
        own fix, so a manual check such as task 4.1 passes without exercising the fix, and so do the vector tests.
        Only the tests in `test_cli_misc.py` that remove the variable still protect the fix.
      - "seen in a Claude Code session" is imprecise: the **PowerShell** tool exports it, the Bash tool does not
        (measured in the same session: `[utf-8:surrogateescape]` vs. unset); no PowerShell profile sets it.
      - Its first line is longer than the 120 columns used in the rest of the file.

      (a) `CLAUDE.md:115-117` — replace the whole bullet (from `- **Agent sessions may export` to
          `` `Remove-Item Env:PYTHONIOENCODING`. ``) with:

          ```markdown
          - **Claude Code's PowerShell tool exports `PYTHONIOENCODING=utf-8:surrogateescape`** (its Bash tool does not;
            it is not set at user or machine level). The suite is green with or without it, but while it is set the CLI
            honors it and skips its own UTF-8 fix, so a manual check such as `markitdown f > out.md` proves nothing.
            Run `Remove-Item Env:PYTHONIOENCODING` before verifying CLI output by hand, and before measuring a baseline
            on commits older than `mk001` (they show 10 failures instead of 4 with the variable set).
          ```

      (b) `CLAUDE.md:109` — `1140 passed, 49 skipped, 0 failed` → `1141 passed, 49 skipped, 0 failed`, **after** R1
          (task 3.2) is done and the full suite has confirmed the number. Use the measured number if it differs.
      (c) Commit `docs(mk001-windows-test-fixes): correct the PYTHONIOENCODING note and the baseline count` and push.
          Then tick this task.

- [x] 5.2 `CLAUDE.md`, section "What this repo is" — after its last bullet (line 18) add:
      `- Other coding agents start from [`AGENTS.md`](AGENTS.md), which points here.`

- [x] 5.3 `CLAUDE.md`, section "Decision log" (last section) — append:

      ```markdown
      - 2026-11-13 (`mk001-windows-test-fixes`): the CLI writes UTF-8 to a stdout that is not a terminal (an explicit
        `PYTHONIOENCODING` wins), fixing silent character loss with `>` and `|` on Windows; the suite is green on Windows
        without `PYTHONUTF8`. Change confined to `__main__.py::_handle_output`. Linux verification: see
        `linux-verification-results.md` in the archived change folder.
      ```

- [x] 5.4 Commit `docs(mk001-windows-test-fixes): update baseline and CLI notes` and push.

## 6. Local final verification

Unticked by the review of 2026-11-13: all three passed at `5ddd389` (re-run by the reviewer, same results), but they are
the gate before group 7 and must be run again after adjustments R1 (task 3.2) and R2 (task 5.1) are committed.

- [ ] 6.1 `uvx black==26.10.1 --check packages/markitdown/src/markitdown/__main__.py packages/markitdown/tests/test_cli_misc.py packages/markitdown/tests/test_cli_vectors.py`
      → `3 files would be left unchanged.`
- [ ] 6.2 `git diff main --stat -- packages` lists exactly those three files.
- [ ] 6.3 `openspec validate mk001-windows-test-fixes --strict` → valid. Push the branch.

## Review of groups 1–6 (2026-11-13, on the development machine)

Independent re-verification of the implementation at `5ddd389`. Windows 11, Python 3.13, `GITHUB_ACTIONS=1`; every
run with `PYTHONIOENCODING` and `PYTHONUTF8` unset unless stated. All results below were measured, not read from the
implementation's report.

| Check | Result |
|---|---|
| Full suite | `1140 passed, 49 skipped`, 0 failed (matches 3.3) |
| Full suite with `PYTHONIOENCODING=utf-8:surrogateescape` left set | `1140 passed, 49 skipped` |
| `test_cli_misc.py` + `test_cli_vectors.py` with `PYTHONUTF8=1` (upstream CI setting) | `89 passed, 20 skipped` |
| Negative control: `main`'s `__main__.py` + the four new tests | 2 failed, 2 passed — the two expected on Windows |
| `test_convert_url` (network; its line changed in 2.3 is skipped by `GITHUB_ACTIONS`) | `20 passed` |
| `mypy --warn-unused-ignores` on `__main__.py` and `test_cli_misc.py` | clean; both `type: ignore` codes are needed and correct |
| black 26.10.1, `git diff main --stat -- packages`, `openspec validate --strict` | clean / three files / valid |
| End to end in Git Bash, cmd.exe and PowerShell 7.7 (see 4.1) | valid UTF-8, equal to `-o` |
| Line endings and encoding of the committed files | LF in the index, no BOM |

Findings:

- **R1 (code, low severity) — task 3.2 reopened.** A replaced `sys.stdout` without `isatty` raises `AttributeError`;
  it works on `main`.
- **R2 (docs) — task 5.1 reopened.** The `PYTHONIOENCODING` note added to `CLAUDE.md` describes the pre-change
  behavior and misses the consequence that remains.
- Tasks 6.1–6.3 unticked only because they must be repeated after R1 and R2.

Not reopened — observations for the owner, no action required by this change:

- `PYTHONIOENCODING=:replace` (an error handler without an encoding) also disables the fix, so the output is lossy
  cp1252 again (measured). This follows the spec as written ("set to a non-empty value"), but the helper's docstring
  says "no encoding was explicitly requested", which is not what the code checks. If this matters, the check would be
  `os.environ.get("PYTHONIOENCODING", "").split(":")[0]` plus a spec scenario; otherwise leave it.
- Text already buffered in stdout before `_handle_output` is flushed in the old encoding when `reconfigure` runs
  (measured with a fake stream). The CLI itself writes nothing before the Markdown; `_youtube_converter.py:135,196,251`
  print error messages to stdout (upstream behavior, network converter), which is the "CLI errors on stdout" item
  already tracked in `PLAN.md`.
- Everything else in groups 1–5 was implemented as specified: the red phase (28 failed) is consistent with the
  negative control above, commits are scoped and pushed, and no file outside the three listed ones changed under
  `packages`.

## 7. Linux verification — PENDING, on the second machine (Podman), any agent

**Blocked until tasks 3.2, 5.1 and 6.1–6.3 are ticked again** (review adjustments R1 and R2). A run made before that
would verify code that is about to change.

Do this only after groups 1–6 are pushed. Full step-by-step instructions, expected results, the results template and
troubleshooting are in [`linux-verification.md`](linux-verification.md) (same folder). The second machine reports only:
it does not change source, tests or the script.

- [ ] 7.1 Follow steps 0 and 1 of `linux-verification.md`: run `linux-verify.sh` inside
      `docker.io/library/python:3.12-slim` and again inside `docker.io/library/python:3.13-slim`.

      ```
      podman run --rm docker.io/library/python:3.12-slim bash -c "apt-get update -qq && apt-get install -y -qq git > /dev/null && git clone -q --branch feature/mk001-windows-test-fixes https://github.com/jorcanha/markitdown /work && cd /work && bash openspec/changes/mk001-windows-test-fixes/linux-verify.sh" > linux-run-py312.log 2>&1
      ```

      Expected `RESULT` lines: `PRECONDITION: PASS`, `INSTALL: PASS`, `A: PASS` (no `failed`), `B: PASS` (without the fix
      only `test_redirected_stdout_is_utf8_even_with_legacy_locale` fails), `C: PASS` (identical SHA-256, valid UTF-8),
      `WORKTREE: PASS`; exit status 0. The expectations for B and C come from analysis and were never observed on Linux.
- [ ] 7.2 Follow steps 2 and 3 of `linux-verification.md`: write `linux-verification-results.md` from the template
      (verbatim `RESULT` lines for both Python versions, tested commit, deviations, verdict), tick 7.1 and 7.2, commit
      `test(mk001-windows-test-fixes): record Linux verification results` with only those two files, and push to
      `feature/mk001-windows-test-fixes`. Tick both tasks even if a check failed; the verdict line says how it went.
- [ ] 7.3 Back on the development machine: `git pull`, read `linux-verification-results.md`. All checks passed on both
      versions → change `PLAN.md:22` from `- [~]` to `- [x]` and run `/opsx:archive`. Anything else → decide whether the
      spec scenario ("POSIX behavior unchanged", "Encoding defects are reproducible on any operating system") or the
      implementation is wrong, fix it on this branch, and repeat group 7 before archiving.
