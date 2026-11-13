# Fork roadmap

Status: `[ ]` pending · `[~]` in progress · `[x]` done. Update this file as work progresses.
Each feature item becomes an OpenSpec change `mkNNN-<name>` on its own branch (see `CLAUDE.md`);
note the change id next to the item when it is started.
IDs in parentheses such as (C4) or (S5) refer to findings in
[`docs/reviews/2026-11-13-project-review.md`](docs/reviews/2026-11-13-project-review.md).

## Phase 0 — Setup

- [x] Merge `microsoft/markitdown` history into this repo (`upstream` remote).
- [x] LICENSE with Microsoft's copyright + fork maintainer's; fork notice in README.
- [x] Create `CLAUDE.md` (agent guide) and this `PLAN.md`.
- [x] Local environment with `uv` and a baseline test run.
- [x] Point `pyproject.toml` project URLs to the fork and add the maintainer. **Do not** publish to PyPI as `markitdown`
      (name taken; use a different name if ever published).
- [x] Initialize OpenSpec with project rules (`mkNNN` ids, branch per change, English-only repo content).
- [x] Disable GitHub Actions for now (`.github/workflows-disabled/`).
- [x] Full project review: code, tests, docs, specs, security (`docs/reviews/2026-11-13-project-review.md`).
- [~] **`mk001-windows-test-fixes`**: green test suite on Windows, plus the two CLI defects it uncovered — redirected
      stdout not UTF-8 (C2) and piped stdin broken (C1).
- [ ] Fork notes in `SECURITY.md` / `SUPPORT.md` (they still point to Microsoft) and fork URLs in the other three
      `pyproject.toml` files (D3, D4).
- [ ] Re-enable GitHub Actions once the project is improved: add a Windows job and Python 3.13, run the other packages'
      tests, and confirm on Linux the behavior that `mk001` could only reason about (T5, T6).
- [ ] Keep GitHub's Dependabot **alerts** on (repository setting; uses no Actions minutes) (S10).

## Phase 1 — Understand and measure (no behavior change)

- [ ] Gather a representative set of test PDFs from real use (prose, tables, scanned, multi-column) — outside the repo if private.
- [ ] `scripts/benchmark_tokens.py`: convert a folder **in one process** (CLI start-up is ~2.7 s per call, C9) and report
      per file: PDF size, output characters, approx. tokens and time. Optional: exact counts via Anthropic's token
      counting API. Also measure whether CRLF line endings in Windows output change the token count.
- [ ] Golden-output (characterization) tests for `converters/_pdf_converter.py`, currently at 66 % coverage with no
      output snapshots, so that Phase 2 refactors are safe (T3, T4).
- [ ] Compare against alternatives (e.g. `docling`; `pymupdf4llm` for local evaluation only — AGPL, S11) on quality and
      tokens to decide where to invest.

## Phase 2 — Safe defaults (hardening)

Small, mostly opt-out-able changes that make the tool safe for private documents. Do these before Phase 4.

- [ ] **Audio transcription opt-in**: converting audio/video must not upload it to Google unless explicitly requested
      (flag and keyword argument; default off) (S6).
- [ ] **Resource limits**: ZIP member count, expanded size and nesting depth; HTTP timeout and maximum download size (S5, C10).
- [ ] **`file:` URIs on Windows**: reject UNC targets (S4).
- [ ] CLI error messages to stderr (C3); silence the `pydub` warning when `ffmpeg` is absent (C12).
- [ ] Use `defusedxml` in `converter_utils/docx/pre_process.py` (S7).
- [ ] Make `MarkItDown.convert_stream()` detect non-rewindable streams reliably on Windows (library side of C1).
- [ ] Correctness fixes: CSV cell escaping (C4), literal `None` on charset-detection failure (C5), RSS title/unbound
      variable (C6), `print()` in the YouTube converter (C7), exiftool output decoding (C14).

## Phase 3 — PDF improvements (opt-in, with tests)

Ordered by impact/effort for saving tokens and improving LLM comprehension:

1. [ ] **Noise cleanup**: drop headers/footers repeated across many pages and standalone page numbers.
2. [ ] **Text reflow**: rejoin end-of-line hyphenated words and hard-wrapped paragraph lines.
3. [ ] **Character cleanup**: ligatures (`ﬁ`→`fi`), `(cid:NN)`, repeated spaces, control characters.
4. [ ] Optional **page markers** (`<!-- page 3 -->`) for citations.
5. [ ] **Headings**: infer `#`/`##` from font size (pdfplumber exposes per-char `size`).
6. [ ] **Performance**: avoid double parsing (pdfplumber + pdfminer) when there are no forms.
7. [ ] Remove dead code `_extract_tables_from_words` (or reuse it).
8. [ ] Detect scanned PDFs (no text layer) and warn clearly instead of returning empty output; optional local OCR
       (e.g. Tesseract) with no token cost.
9. [ ] Optional stripping of invisible text (white-on-white, zero-size) to reduce prompt-injection surface (S2).

## Phase 4 — Claude workflow

- [ ] Batch conversion of a folder: `markitdown-batch <folder> -o <output>` (recursive, skip already converted, error
      log), implemented in process, not by spawning the CLI per file (C9).
- [ ] **MCP hardening — prerequisite for the next item**: upgrade `mcp` past the known advisories (S3); restrict the tool
      to an allow-listed root directory; no `http(s):` by default; size limits; no `debug=True`; do not block the event
      loop; add tests (the package has none) (S1, C11, T5).
- [ ] Configure `markitdown-mcp` in Claude Code / Claude Desktop and document it here.
- [ ] Optional "compact" mode applying all Phase 3 cleanups at once (`--compact`).
- [ ] If image description or OCR through Claude is wanted: adapter for the OpenAI-shaped `llm_client` (C13).

## Phase 5 — Maintenance

- [ ] Periodically sync with `upstream/main` and record relevant conflicts in `CLAUDE.md`.
- [ ] Consider proposing generic fixes upstream (the two CLI fixes from `mk001` are good candidates). Security-relevant
      items (S4, S5) go through the process in `SECURITY.md`, not public issues. Only on the owner's explicit request.
- [ ] `markitdown-ocr`: investigate the failing `test_pdf_multipage` (T5).
