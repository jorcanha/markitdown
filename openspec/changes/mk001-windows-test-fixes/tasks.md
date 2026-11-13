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

- [x] 3.3 Green phase: `$env:GITHUB_ACTIONS = "1"; .venv\Scripts\python -m pytest packages/markitdown/tests -q -p no:cacheprovider`
      → expected `1140 passed, 49 skipped`, no `failed`.
- [x] 3.4 Commit `fix(mk001-windows-test-fixes): write UTF-8 when stdout is redirected or piped` (body: output changes from
      the ANSI code page to UTF-8 on Windows; `PYTHONIOENCODING` restores a legacy encoding) and push.

## 4. Manual verification (PowerShell 7)

- [ ] 4.1 Redirect and `-o` give the same UTF-8 text:

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

- [ ] 5.2 `CLAUDE.md`, section "What this repo is" — after its last bullet (line 18) add:
      `- Other coding agents start from [`AGENTS.md`](AGENTS.md), which points here.`

- [ ] 5.3 `CLAUDE.md`, section "Decision log" (last section) — append:

      ```markdown
      - 2026-11-13 (`mk001-windows-test-fixes`): the CLI writes UTF-8 to a stdout that is not a terminal (an explicit
        `PYTHONIOENCODING` wins), fixing silent character loss with `>` and `|` on Windows; the suite is green on Windows
        without `PYTHONUTF8`. Change confined to `__main__.py::_handle_output`. Linux verification: see
        `linux-verification-results.md` in the archived change folder.
      ```

- [ ] 5.4 Commit `docs(mk001-windows-test-fixes): update baseline and CLI notes` and push.

## 6. Local final verification

- [ ] 6.1 `uvx black==26.10.1 --check packages/markitdown/src/markitdown/__main__.py packages/markitdown/tests/test_cli_misc.py packages/markitdown/tests/test_cli_vectors.py`
      → `3 files would be left unchanged.`
- [ ] 6.2 `git diff main --stat -- packages` lists exactly those three files.
- [ ] 6.3 `openspec validate mk001-windows-test-fixes --strict` → valid. Push the branch.

## 7. Linux verification — PENDING, on the second machine (Podman), any agent

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
