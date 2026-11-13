<!--
Line numbers refer to the files as of commit 7fc4e5a on main (unchanged on this branch). If a file has moved, locate
the edit by the quoted "before" code. All paths are relative to the repository root. Commands are PowerShell.
The whole change was prototyped and reverted: tests only → 20 failed / 164 passed / 33 skipped; tests + fixes →
184 passed / 33 skipped / 0 failed; `uvx black==23.7.0 --check` clean on the four touched files.
-->

## 1. Preparation

- [ ] 1.1 Confirm the branch and the starting point.

      ```powershell
      git status -sb                      # expect: ## feature/mk001-windows-test-fixes
      $env:GITHUB_ACTIONS = "1"
      .venv\Scripts\python -m pytest packages/markitdown/tests -q -p no:cacheprovider
      ```

      Expected last line: `41 failed, 138 passed, 33 skipped`.

## 2. Tests first (red phase)

- [ ] 2.1 `packages/markitdown/tests/test_cli_misc.py:2-3` — imports and shared constants.

      Before:

      ```python
      import subprocess
      from markitdown import __version__
      ```

      After:

      ```python
      import argparse
      import io
      import os
      import subprocess
      import sys

      from markitdown import __version__, DocumentConverterResult
      from markitdown.__main__ import _handle_output

      TEST_FILES_DIR = os.path.join(os.path.dirname(__file__), "test_files")

      # Accents (representable in cp1252) plus CJK and symbols (not representable).
      NON_ASCII_MARKDOWN = "José | 名前 | → ✓"
      ```

- [ ] 2.2 `packages/markitdown/tests/test_cli_misc.py:10-12` (`test_version`) and `:19-21` (`test_invalid_flag`) — use the
      running interpreter and decode as UTF-8 (design D1, D2).

      Before (`:10-12`; `:19-21` is identical with `"--foobar"`):

      ```python
          result = subprocess.run(
              ["python", "-m", "markitdown", "--version"], capture_output=True, text=True
          )
      ```

      After:

      ```python
          result = subprocess.run(
              [sys.executable, "-m", "markitdown", "--version"],
              capture_output=True,
              text=True,
              encoding="utf-8",
          )
      ```

- [ ] 2.3 `packages/markitdown/tests/test_cli_misc.py` — insert the new tests after `test_invalid_flag` (after line 27,
      before the `if __name__ == "__main__":` block at line 30) (design D7; specs `cli-output-encoding`).

      ```python
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


      def test_cli_redirected_stdout_is_utf8() -> None:
          """End to end: a captured (non-TTY) stdout is valid UTF-8 on every OS."""
          env = {k: v for k, v in os.environ.items() if k != "PYTHONIOENCODING"}
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

      Leave the `if __name__ == "__main__":` block as it is (the new tests need pytest's `monkeypatch`).

- [ ] 2.4 `packages/markitdown/tests/test_cli_vectors.py:6` — replace `import locale` with `import sys` (design D2).

- [ ] 2.5 `packages/markitdown/tests/test_cli_vectors.py:49`, `:72`, `:107`, `:158` — replace the list element `"python",`
      with `sys.executable,` (design D1). Then `:138` (`test_convert_url`), which no longer fits on one line:

      Before:

      ```python
              ["python", "-m", "markitdown", TEST_FILES_URL + "/" + test_vector.filename],
      ```

      After:

      ```python
              [
                  sys.executable,
                  "-m",
                  "markitdown",
                  TEST_FILES_URL + "/" + test_vector.filename,
              ],
      ```

- [ ] 2.6 `packages/markitdown/tests/test_cli_vectors.py` — explicit UTF-8 everywhere (design D2).

      - `:55`, `:80`, `:167` — after each `text=True,` add the line `encoding="utf-8",`.
      - `:86`, `:173` — `with open(output_file, "r") as f:` → `with open(output_file, "r", encoding="utf-8") as f:`.
      - `:117`, `:143` — `result.stdout.decode(locale.getpreferredencoding())` → `result.stdout.decode("utf-8")`.

- [ ] 2.7 `packages/markitdown/tests/test_cli_vectors.py:99-115` (`test_input_from_stdin_without_hints`) — really read from
      stdin (design D5; spec `cli-stdin-input`). Fix the docstring typo at `:99` and delete the filename argument at `:110`.

      Before (`:99` and `:105-115`):

      ```python
          """Test that the CLI readds from stdin correctly."""
      ```

      ```python
          result = subprocess.run(
              [
                  "python",
                  "-m",
                  "markitdown",
                  os.path.join(TEST_FILES_DIR, test_vector.filename),
              ],
              input=test_input,
              capture_output=True,
              text=False,
          )
      ```

      After:

      ```python
          """Test that the CLI reads from stdin correctly (no filename, no hints)."""
      ```

      ```python
          result = subprocess.run(
              [
                  sys.executable,
                  "-m",
                  "markitdown",
              ],
              input=test_input,
              capture_output=True,
              text=False,
          )
      ```

- [ ] 2.8 `packages/markitdown/tests/test_module_misc.py:5-6` — add `import sys` between `import shutil` and
      `import pytest`.

- [ ] 2.9 `packages/markitdown/tests/test_module_misc.py:223-252` (`test_file_uris`) — platform-aware expectation
      (design D6). Insert at the top of the function body (after line 223) and replace the five assertions at `:228`,
      `:234`, `:240`, `:246`, `:252`.

      Insert:

      ```python
          # file_uri_to_path() returns an absolute, platform-native path:
          # "/path/to/file.txt" on POSIX, "<current drive>:\path\to\file.txt" on Windows.
          expected_path = os.path.abspath("/path/to/file.txt")

      ```

      Replace (five times) `assert path == "/path/to/file.txt"` with `assert path == expected_path`.

- [ ] 2.10 `packages/markitdown/tests/test_module_misc.py` — add the Windows-only test after `test_file_uris` (after line
      252, before `def test_docx_comments` at line 255) (design D6).

      ```python
      @pytest.mark.skipif(sys.platform != "win32", reason="Windows drive-letter file URIs")
      def test_file_uris_windows_drive() -> None:
          netloc, path = file_uri_to_path("file:///C:/path/to/file.txt")
          assert netloc is None
          assert path == "C:\\path\\to\\file.txt"
      ```

- [ ] 2.11 Confirm the red phase: the tests now fail only for the two CLI defects.

      ```powershell
      $env:GITHUB_ACTIONS = "1"
      .venv\Scripts\python -m pytest packages/markitdown/tests -q -p no:cacheprovider
      ```

      Expected last line: `20 failed, 164 passed, 33 skipped`. The 20 failures must be exactly:
      12 × `test_cli_vectors.py::test_input_from_stdin_without_hints` (stdin defect),
      6 × `test_cli_vectors.py::test_output_to_stdout` (stdout is not UTF-8),
      `test_cli_misc.py::test_redirected_stdout_is_utf8_even_with_legacy_locale` and
      `test_cli_misc.py::test_cli_redirected_stdout_is_utf8`. Anything else failing means a task above was applied wrongly.

- [ ] 2.12 Commit: `test(mk001-windows-test-fixes): make CLI tests portable and cover stdout/stdin defects`
      (say in the body that 20 tests fail on Windows until the next commit) and push.

## 3. CLI fixes (green phase)

- [ ] 3.1 `packages/markitdown/src/markitdown/__main__.py:4-5` — imports. Keep the SPDX header (lines 1-3) untouched.

      Before:

      ```python
      import argparse
      import sys
      ```

      After:

      ```python
      import argparse
      import io
      import os
      import sys
      ```

- [ ] 3.2 `packages/markitdown/src/markitdown/__main__.py:189-194` (`main`, stdin branch) — buffer stdin (design D4).

      Before:

      ```python
          if args.filename is None:
              result = markitdown.convert_stream(
                  sys.stdin.buffer,
                  stream_info=stream_info,
                  keep_data_uris=args.keep_data_uris,
              )
      ```

      After:

      ```python
          if args.filename is None:
              # Read stdin fully before converting. A pipe cannot be rewound, but on
              # Windows BufferedReader.seekable() reports True for pipes, so
              # convert_stream() would skip its own buffering and the converters would
              # read a half-consumed stream (empty output or a failed conversion).
              result = markitdown.convert_stream(
                  io.BytesIO(sys.stdin.buffer.read()),
                  stream_info=stream_info,
                  keep_data_uris=args.keep_data_uris,
              )
      ```

- [ ] 3.3 `packages/markitdown/src/markitdown/__main__.py:208-214` (`_handle_output`, stdout branch) — UTF-8 for a
      non-terminal stdout (design D3).

      Before:

      ```python
          else:
              # Handle stdout encoding errors more gracefully
              print(
                  result.markdown.encode(sys.stdout.encoding, errors="replace").decode(
                      sys.stdout.encoding
                  )
              )
      ```

      After:

      ```python
          else:
              # A redirected or piped stdout uses the locale encoding (e.g. cp1252 on
              # Windows), which silently destroys text outside that code page. Emit
              # UTF-8 instead, unless the user explicitly asked for another encoding.
              if _should_force_utf8_stdout():
                  sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[union-attr]

              # Handle stdout encoding errors more gracefully
              print(
                  result.markdown.encode(sys.stdout.encoding, errors="replace").decode(
                      sys.stdout.encoding
                  )
              )
      ```

- [ ] 3.4 `packages/markitdown/src/markitdown/__main__.py` — add the helper between `_handle_output` and
      `_exit_with_error` (before line 217), with two blank lines above and below (design D3).

      ```python
      def _should_force_utf8_stdout() -> bool:
          """True when stdout is not a terminal and no encoding was explicitly requested."""
          return (
              not sys.stdout.isatty()
              and not os.environ.get("PYTHONIOENCODING")
              and hasattr(sys.stdout, "reconfigure")
          )
      ```

- [ ] 3.5 Confirm the green phase.

      ```powershell
      $env:GITHUB_ACTIONS = "1"
      .venv\Scripts\python -m pytest packages/markitdown/tests -q -p no:cacheprovider
      ```

      Expected last line: `184 passed, 33 skipped` (no `failed`).

- [ ] 3.6 Commit: `fix(mk001-windows-test-fixes): UTF-8 for redirected stdout and buffered stdin in the CLI`. In the body:
      redirected/piped output changes from the locale code page to UTF-8 on Windows; `PYTHONIOENCODING` restores a legacy
      encoding. Push.

## 4. Manual verification on Windows

- [ ] 4.1 Redirected stdout and `-o` give the same UTF-8 text in PowerShell 7 (scratch files outside the repo).

      ```powershell
      $t = Join-Path $env:TEMP "mk001"; New-Item -ItemType Directory -Force $t | Out-Null
      "name,city,note`nJosé,Bogotá,→ ✓ €`n名前,東京,x" | Set-Content "$t\sample.csv" -Encoding utf8
      .venv\Scripts\markitdown.exe "$t\sample.csv" 2>$null > "$t\redirect.md"
      .venv\Scripts\markitdown.exe "$t\sample.csv" -o "$t\file.md" 2>$null
      (Get-Content "$t\redirect.md" -Raw -Encoding utf8).TrimEnd() -eq (Get-Content "$t\file.md" -Raw -Encoding utf8).TrimEnd()
      Select-String -Path "$t\redirect.md" -Pattern "名前" -Encoding utf8 -Quiet
      ```

      Expected: `True` and `True`.

- [ ] 4.2 Piped stdin converts a binary and a text document.

      ```powershell
      cmd /c "type packages\markitdown\tests\test_files\test.pdf | .venv\Scripts\markitdown.exe -o %TEMP%\mk001\stdin_pdf.md" 2>$null
      cmd /c "type packages\markitdown\tests\test_files\test.json | .venv\Scripts\markitdown.exe -o %TEMP%\mk001\stdin_json.md" 2>$null
      Select-String -Path "$env:TEMP\mk001\stdin_pdf.md" -Pattern "contemporaneous exploration" -Quiet
      Select-String -Path "$env:TEMP\mk001\stdin_json.md" -Pattern "5b64c88c-b3c3-4510-bcb8-da0b200602d8" -Quiet
      ```

      Expected: `True` and `True`. Then `Remove-Item -Recurse $env:TEMP\mk001`.

## 5. Documentation

- [ ] 5.1 `CLAUDE.md:84-90` — the setup block no longer needs activation.

      Before (`:87-89`):

      ```powershell
      .venv\Scripts\Activate.ps1          # needed: CLI tests spawn "python"
      python -m pytest packages/markitdown/tests -q
      markitdown file.pdf -o output.md
      ```

      After:

      ```powershell
      $env:GITHUB_ACTIONS = "1"           # skips tests that need the network
      .venv\Scripts\python -m pytest packages/markitdown/tests -q
      .venv\Scripts\markitdown file.pdf -o output.md
      ```

- [ ] 5.2 `CLAUDE.md:100-105` — replace the "Windows baseline" bullet and its three sub-bullets.

      After:

      ```markdown
      - **Windows baseline (`GITHUB_ACTIONS=1`, after `mk001`)**: 184 passed, 33 skipped, 0 failed. Tests launch the CLI with
        `sys.executable`; never spawn a bare `"python"` in a test (on Windows it resolves to the base interpreter, even with
        the venv activated). Without `GITHUB_ACTIONS`, network tests and `test_speech_transcription` (needs `ffmpeg`) still fail.
      - **CLI output on Windows**: prefer `markitdown <file> -o <out.md>`; it is UTF-8 in every shell. A redirected or piped
        stdout is UTF-8 too (unless `PYTHONIOENCODING` is set), but Windows PowerShell 5.1 (`>`) and PowerShell pipelines into
        cmdlets or variables re-encode a native command's output and can still corrupt non-ASCII text.
      - **CLI input**: `cat file | markitdown` and `markitdown < file` both work; the CLI buffers stdin in memory.
      ```

- [ ] 5.3 `CLAUDE.md:76` — in the CI section, replace `(fix the Windows test issues below first, and consider adding a
      Windows job)` with `(add a Windows job, and confirm on Linux what mk001 could only reason about)`.

- [ ] 5.4 `CLAUDE.md`, section "Decision log" (last section) — append:

      ```markdown
      - 2026-11-13 (`mk001-windows-test-fixes`): test suite green on Windows. The CLI now writes UTF-8 to a non-terminal stdout
        (explicit `PYTHONIOENCODING` wins) and buffers stdin, fixing silent data loss with `>` and `|` on Windows. Fixes live
        only in `__main__.py`; `convert_stream()` itself still trusts `seekable()` (follow-up in `PLAN.md`). Not run on Linux.
      ```

- [ ] 5.5 `PLAN.md:20-21` — change `- [~] **\`mk001-windows-test-fixes\`**` to `- [x]` (do this in the archive step).

- [ ] 5.6 Commit: `docs(mk001-windows-test-fixes): update Windows baseline and CLI notes`. Push.

## 6. Final verification

- [ ] 6.1 Full suite once more: `$env:GITHUB_ACTIONS = "1"; .venv\Scripts\python -m pytest packages/markitdown/tests -q -p no:cacheprovider`
      → `184 passed, 33 skipped`.

- [ ] 6.2 Formatting with the pinned black, touched files only:

      ```powershell
      uvx black==23.7.0 --check packages/markitdown/src/markitdown/__main__.py packages/markitdown/tests/test_cli_misc.py packages/markitdown/tests/test_cli_vectors.py packages/markitdown/tests/test_module_misc.py
      ```

      Expected: `4 files would be left unchanged.` If not, run the same command without `--check` and commit the result.

- [ ] 6.3 `git diff main --stat -- packages` lists exactly four files: `__main__.py`, `test_cli_misc.py`,
      `test_cli_vectors.py`, `test_module_misc.py`.

- [ ] 6.4 `openspec validate mk001-windows-test-fixes --strict` → `Change 'mk001-windows-test-fixes' is valid`.
