# Project review — 2026-11-13

Full review of the fork at `main` = `ab7f71e` (upstream `a51f725`, version `0.1.6b2`) plus the first OpenSpec change
(`mk001-windows-test-fixes`). Covers source code, tests, documentation, specs and security.

**How to read the "Verified" column**

- **run** — reproduced by executing code on the development machine (Windows 11, Python 3.13.13, PowerShell 7.7.0,
  Windows PowerShell 5.1, cmd.exe, Git Bash; network tests skipped with `GITHUB_ACTIONS=1`).
- **read** — found by reading the code; not executed.

Nothing here was run on Linux: CI is disabled and the machine has neither WSL nor Docker.

## 1. Summary

- The code base is small (about 4,600 lines in the main package) and easy to follow. The converter contract
  (`accepts` / `convert`, priority-ordered registry) is a good base for the PDF work this fork is about.
- **The CLI is broken on Windows in two ways that lose data silently**: redirected stdout is not UTF-8, and piped stdin
  yields empty output or a failed conversion. Both are now part of `mk001`.
- **Starting with `mk001` is the right call** (a green test suite before touching the PDF converter), but the first
  draft of the spec had gaps; see section 5.
- **Security**: the core dependency set is clean. The risks that matter for this fork's use (documents → Markdown →
  Claude) are the MCP server's unrestricted `file:`/`http:` access, hidden text surviving conversion (prompt
  injection), no resource limits on archives and downloads, and audio files being uploaded to a third-party service by
  default. None of them blocks local, manual conversion of the owner's own PDFs.
- **Tests**: 68 % line coverage in process; the PDF converter is at 66 % and has no golden-output tests, which is the
  first thing to fix before refactoring it.

## 2. Source code

| ID | Finding | Evidence | Verified |
|---|---|---|---|
| C1 | **Piped stdin is broken on Windows.** `cat f \| markitdown` gives empty output with exit 0 for text formats and `BadZipFile` / `PDFKeyError` for binary ones; 0 of 12 test vectors convert. `sys.stdin.buffer.seekable()` is `True` for a Windows pipe, so `convert_stream` skips its buffering. `markitdown < f` works. | `__main__.py:189-194`, `_markitdown.py:370` | run |
| C2 | **Redirected stdout is not UTF-8 on Windows.** cp1252 with `errors="replace"`: invalid UTF-8 for accents, `?` for anything else. `-o` is correct. | `__main__.py:208-214` | run |
| C3 | CLI error messages are printed to **stdout**, so `markitdown … > out.md` writes the error into the file (exit code is 1). | `__main__.py:217-219` | run |
| C4 | CSV cells containing `\|` or a newline are not escaped, producing a broken Markdown table. | `_csv_converter.py:61-73` | run |
| C5 | When charset detection fails, `str(from_bytes(...).best())` returns the literal text `None`. | `_plain_text_converter.py:69`, `_csv_converter.py:48` | read |
| C6 | RSS: a `<channel>` without `<title>` takes the first item's title (descendant lookup); `md_text` is unbound when there is no title at all; `except BaseException` swallows `KeyboardInterrupt`; per-call state stored on the shared converter instance. | `_rss_converter.py:143-149`, `:68`, `:176`, `:90` | run (first), read (rest) |
| C7 | The YouTube converter prints diagnostics with `print()`, polluting Markdown written to stdout. | `_youtube_converter.py:115`, `:179`, `:233` | read |
| C8 | PDF converter: 95 lines of dead code (`_extract_tables_from_words`); every prose PDF is parsed twice (pdfplumber, then pdfminer); no heading or list detection; repeated headers/footers and page numbers are kept; scanned PDFs return empty text. | `_pdf_converter.py:398-492`, `:552-572` | read |
| C9 | **CLI start-up costs 2.6–2.9 s per invocation**, all of it imports (pandas, Azure SDK, speech, ONNX…); converting a small file then takes 0.01 s. Batch conversion must run in one process, and lazy imports are worth considering. | measured: `--version` 2.9 s; in-process import 2.6 s | run |
| C10 | `requests.get` has no timeout; `convert_response` and `ZipConverter` read unbounded data into memory (see S5). `PlainTextConverter` imports `mammoth` without using it. | `_markitdown.py:452`, `:527-530`, `_plain_text_converter.py:12` | read |
| C11 | MCP tool is `async` but calls the blocking `convert_uri`, and builds a new `MarkItDown` on every call. | `markitdown_mcp/__main__.py:20-23` | read |
| C12 | `pydub` prints a `RuntimeWarning` to stderr on every CLI start when `ffmpeg` is missing. | observed on every run | run |
| C13 | Image captioning and the OCR plugin call `client.chat.completions.create` (OpenAI client shape). Using Claude needs an OpenAI-compatible endpoint or an adapter. | `_llm_caption.py:49`, `markitdown_ocr/_ocr_service.py:86` | read |
| C14 | `_exiftool.py` decodes exiftool's UTF-8 JSON with the locale encoding (mojibake on Windows) and spawns a version check on every conversion. | `_exiftool.py:21-28`, `:49` | read |

## 3. Tests

| ID | Finding | Verified |
|---|---|---|
| T1 | Windows baseline: 138 passed, 33 skipped, **41 failed**. 40 are CLI tests that spawn `"python"`, which resolves to the base interpreter on Windows even with the venv activated; 1 is `test_file_uris` hard-coding POSIX paths. | run |
| T2 | `test_input_from_stdin_without_hints` passes the filename as well as stdin, so stdin was never tested — which is why C1 went unnoticed upstream. | run |
| T3 | Coverage (in process, network skipped): **68 %** overall. `__main__.py` 0 % (subprocess only), `_youtube_converter.py` 14 %, audio/exiftool about 35 %, `_rss_converter.py` 59 %, `_markitdown.py` 63 %, **`_pdf_converter.py` 66 %**. | run |
| T4 | No golden-output tests and nothing that measures output size. The fork's goal (fewer tokens) is not measurable yet. | read |
| T5 | Other packages on Windows: `markitdown-sample-plugin` 2 passed; `markitdown-ocr` 35 passed, 1 failed (`test_pdf_multipage` expects pdfplumber to fail on a truncated PDF, but pdfplumber 0.11.10 opens it — probably dependency drift); `markitdown-mcp` has **no tests**. Upstream CI does not run any of the three. | run |
| T6 | Upstream CI covers Linux with Python 3.10–3.12 only; the fork develops on Windows with 3.13 (which the classifiers advertise). | read |
| T7 | Network tests are skipped only when `GITHUB_ACTIONS` is set — a misleading name for local runs. | read |
| T8 | A `mypy` environment is configured (`hatch run types:check`) but nothing runs it. | read |

## 4. Documentation

| ID | Finding |
|---|---|
| D1 | `CLAUDE.md` says the venv must be activated for CLI tests. Activation does not help on Windows (T1). Fixed by `mk001`. |
| D2 | `CLAUDE.md` suggests `black packages/`. An unpinned black (26.x) reformats three untouched upstream files; the repo pins 23.7.0 in `.pre-commit-config.yaml`. Use `uvx black==23.7.0 <touched files>`. Fixed in this review. |
| D3 | `SECURITY.md` and `SUPPORT.md` are Microsoft's: they send fork-specific reports to MSRC, and `SUPPORT.md` is still the unedited template. A short fork note is needed. |
| D4 | Only the main package's `pyproject.toml` points to the fork; `markitdown-mcp`, `markitdown-ocr` and `markitdown-sample-plugin` still send `Issues` to upstream. |
| D5 | `PLAN.md` had no security or hardening items and did not gate "use MCP with Claude" on hardening. Fixed in this review. |
| D6 | The README's install line (`pip install 'markitdown[all]'`) installs upstream from PyPI, not the fork. The fork notice covers it; keep in mind when writing fork-specific docs. |

## 5. Specs and OpenSpec setup

`openspec/config.yaml` is sound (context, id convention, branch-per-change, per-artifact rules). Added in this review:
tasks must cite file and line and include the proposed code; every factual claim in an artifact must say how it was
verified; formatting uses the pinned black.

### Review of `mk001-windows-test-fixes` (first draft)

**Verdict: the right first change, with the right size.** Nothing else can be trusted on Windows until the suite is
green, and the draft correctly promoted the stdout encoding defect from "test failure" to "CLI bug".

Gaps found and fixed in the revised artifacts:

| # | Gap in the first draft | Resolution |
|---|---|---|
| 1 | The fake stdin test was deferred as an "open question" because fixing it "may surface new failures". It surfaces C1 — a silent data-loss bug. | Stdin fix and a real stdin test are now in scope; new capability `cli-stdin-input`. |
| 2 | "Redirected stdout is valid UTF-8" was verified only in Git Bash. In Windows PowerShell 5.1 (`>`) and in PowerShell pipelines the shell re-encodes the output, so the scenario over-promised. | Requirement scoped to the bytes the process writes; shell matrix measured in cmd, Git Bash, PowerShell 7 and 5.1; `-o` documented as the shell-independent option. |
| 3 | The only regression test for the stdout fix was a subprocess test, which passes on Linux with or without the fix — and upstream CI is Linux. | In-process tests with a fake cp1252 stdout reproduce the defect on any OS. |
| 4 | The "interactive terminal" requirement had no test. | Covered by a fake-TTY test. |
| 5 | The fix overrode an explicit `PYTHONIOENCODING`. | An explicit `PYTHONIOENCODING` is honored (also the escape hatch for anyone who needs a legacy code page). |
| 6 | The final task ran an unpinned black over the whole package. | Pinned `black==23.7.0`, touched files only. |
| 7 | The spec required the suite to pass "on Linux" with no way to check it. | Stated honestly as an analysis plus a follow-up when CI returns; owner decision recorded as an open question. |
| 8 | Tasks named files but not lines, and gave no code. | Every task has file, line range, before/after code and the expected result; the whole change was prototyped (184 passed, 33 skipped, 0 failed) and reverted. |
| 9 | Only one of the four packages was measured. | Status of the other three recorded as a non-goal with numbers (T5). |

## 6. Security review

Threat model for this fork: a single developer converting documents on their own machine and feeding the Markdown to
an LLM agent (Claude Code, possibly through `markitdown-mcp`). Documents and web pages are **untrusted input**; the
agent has file and network access. Upstream's stated posture (README, "Security Considerations") is that MarkItDown
performs I/O with the caller's privileges and callers must sanitize inputs — several items below are "by design"
upstream but still matter here.

| ID | Severity | Finding | Evidence | Verified |
|---|---|---|---|---|
| S1 | High when the MCP server is used | `convert_to_markdown(uri)` accepts any `file:`, `http(s):` or `data:` URI with no allow-list: every file the user can read and every reachable URL (including localhost and internal addresses) can be pulled into the model's context. Combined with S2, a malicious document can steer the agent into reading local files. HTTP mode has no authentication and runs Starlette with `debug=True`. | `markitdown_mcp/__main__.py:20-23`, `:129` | read |
| S2 | Medium (inherent) | **Converted Markdown is untrusted data.** Text hidden with `display:none` survives HTML conversion; the same is expected for invisible text in PDFs and Office files. HTML comments are dropped and `javascript:` links are neutralized. | probe: hidden paragraph emitted | run (HTML), read (others) |
| S3 | Medium | `markitdown-mcp` pins `mcp~=1.8.0`; `pip-audit` reports 7 advisories for `mcp 1.8.1` (PYSEC-2026-1616, -1617, -1618, -3482, -3483, CVE-2026-59951, CVE-2026-116685), all fixed by 1.30.0. No other package of the 93 installed for the four packages is flagged. | `markitdown-mcp/pyproject.toml:27` | run |
| S4 | Medium (Windows) | The `file:` URI handler rejects URIs with a remote host, but on Windows a UNC path can still be reached through the path component, which would make the process open a remote SMB share (credential exposure, remote content). Checked by parsing only; no network access was attempted. | `_markitdown.py:419-431`, `_uri_utils.py:8-16` | run (parsing) |
| S5 | Medium (denial of service) | No resource limits. A 299 KB ZIP expanded to 300 MB in memory and 300 MB of output in 16 s; nested ZIPs are converted recursively with no depth limit (25 levels checked); HTTP downloads are unbounded and have no timeout. | `_zip_converter.py:96-110`, `_markitdown.py:452`, `:527-530` | run (ZIP), read (HTTP) |
| S6 | Medium (privacy) | **Audio is uploaded to Google's Web Speech API by default.** Converting `.wav`, `.mp3`, `.m4a` or `.mp4` (also inside a ZIP) calls `recognize_google` whenever the `[audio-transcription]` extra is installed — and `[all]` installs it. There is no opt-in. | `_transcribe_audio.py:45-48`, `_audio_converter.py:92-98` | read |
| S7 | Low | `pre_process.py` parses DOCX-derived XML with the standard library's `ElementTree` while the rest of the code uses `defusedxml`. No exploit path was found (no DOCTYPE can be injected inside the wrapper element), but it should be consistent. | `converter_utils/docx/pre_process.py:4`, `:44` | read |
| S8 | Low | Both Dockerfiles build on `python:3.13-slim-bullseye` (Debian 11, past its LTS window). They do run as `nobody`. | `Dockerfile:1`, `markitdown-mcp/Dockerfile:1` | read |
| S9 | Info | Good practices already in place: `defusedxml` for RSS/EPUB/OMML, exiftool invoked without a shell and only from well-known directories with a minimum-version check, plugins off by default, data URIs truncated by default, current pins for `pdfminer.six` and `mammoth`. | — | read |
| S10 | Info | Repository hygiene: no secrets in tracked files; commits use the GitHub no-reply address; `.claude/` holds only the OpenSpec skills. With Actions and Dependabot disabled there is no automated check on pull requests. GitHub's **Dependabot alerts** (a repository setting, no Actions minutes) can stay on. | — | run |
| S11 | Info (licensing, not security) | `markitdown-ocr` depends on PyMuPDF, which is AGPL-3.0 / commercial. `pymupdf4llm`, listed in `PLAN.md` for comparison, has the same license. Fine for local evaluation; do not vendor it or make it a dependency of the MIT-licensed core. | `markitdown-ocr/pyproject.toml:31` | read |

S4 and S5 exist in upstream too. If the owner wants them fixed upstream, `SECURITY.md` asks for reports through MSRC
rather than public issues.

### Practical guidance until the hardening changes land

- Convert only files you chose; do not pass URLs or paths taken from untrusted text to `markitdown`.
- Do not connect `markitdown-mcp` to an agent yet (S1, S3).
- Do not convert audio or video files, or ZIPs that may contain them, unless uploading the audio to Google is acceptable (S6).
- Treat the Markdown as data when giving it to an LLM: do not let instructions inside it trigger tool calls (S2).

## 7. Recommended order of work

1. **`mk001-windows-test-fixes`** (in progress) — green suite on Windows; CLI stdout and stdin fixes.
2. **Token benchmark + PDF golden tests** (`PLAN.md` Phase 1) — measure before changing; raise `_pdf_converter.py`
   coverage with characterization tests so refactors are safe.
3. **Safe defaults** — audio transcription opt-in (S6), ZIP/HTTP limits and timeouts (S5), UNC handling (S4), CLI errors
   to stderr (C3).
4. **PDF improvements** (`PLAN.md` Phase 2) — noise cleanup, reflow, headings, single parse.
5. **MCP hardening** (S1, S3, C11) — a prerequisite for `PLAN.md` Phase 3 ("use MCP with Claude"), not an afterthought.
6. Smaller correctness fixes as convenient: C4, C5, C6, C7, C14, S7.
