# Fork roadmap

Status: `[ ]` pending · `[~]` in progress · `[x]` done. Update this file as work progresses.
Each feature item becomes an OpenSpec change `mkNNN-<name>` on its own branch (see `CLAUDE.md`);
note the change id next to the item when it is started.

## Phase 0 — Setup

- [x] Merge `microsoft/markitdown` history into this repo (`upstream` remote).
- [x] LICENSE with Microsoft's copyright + fork maintainer's; fork notice in README.
- [x] Create `CLAUDE.md` (agent guide) and this `PLAN.md`.
- [x] Local environment with `uv` and a baseline test run.
- [x] Point `pyproject.toml` project URLs to the fork and add the maintainer. **Do not** publish to PyPI as `markitdown`
      (name taken; use a different name if ever published).
- [x] Initialize OpenSpec with project rules (`mkNNN` ids, branch per change, English-only repo content).
- [x] Disable GitHub Actions for now (`.github/workflows-disabled/`).
- [ ] Make the test suite pass on Windows: use `sys.executable` instead of `"python"` in `test_cli_*.py` and adapt
      `test_file_uris` to Windows paths (see `CLAUDE.md`).
- [ ] Re-enable GitHub Actions once the project is improved (optionally add a Windows job).

## Phase 1 — Understand and measure (no behavior change)

- [ ] Gather a representative set of test PDFs from real use (prose, tables, scanned, multi-column) — outside the repo if private.
- [ ] `scripts/benchmark_tokens.py`: convert a folder and report per file: PDF size, output characters, approx. tokens and time.
      Optional: exact counts via Anthropic's token counting API.
- [ ] Compare against alternatives (e.g. `pymupdf4llm`, `docling`) on quality and tokens to decide where to invest.

## Phase 2 — PDF improvements (opt-in, with tests)

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

## Phase 3 — Claude workflow

- [ ] Batch conversion of a folder: `markitdown-batch <folder> -o <output>` (recursive, skip already converted, error log).
- [ ] Configure `markitdown-mcp` in Claude Code / Claude Desktop and document it here.
- [ ] Optional "compact" mode applying all Phase 2 cleanups at once (`--compact`).

## Phase 4 — Maintenance

- [ ] Periodically sync with `upstream/main` and record relevant conflicts in `CLAUDE.md`.
- [ ] Consider proposing generic improvements that work well back to upstream (PR to microsoft/markitdown — only on explicit request).
