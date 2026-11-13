# CLAUDE.md — Agent guide

Living document: any agent (or person) that learns something relevant about this project adds it here.

## Language rule (critical)

- The owner may write prompts in **Spanish or English**. Reply in the language of the prompt.
- Everything committed to the repo is in **English**: code, comments, docstrings, identifiers, tests,
  commit messages, OpenSpec artifacts (proposal, design, specs, tasks) and docs (this file, `PLAN.md`).

## What this repo is

- Personal fork of [microsoft/markitdown](https://github.com/microsoft/markitdown) (MIT), at `https://github.com/jorcanha/markitdown`.
- Goal: convert documents (mainly **PDF**) to Markdown so an LLM (Claude) can process them with fewer tokens;
  adapt the tool to the owner's needs, understand it and improve it.
- Upstream history is merged into `main` (merge with `--allow-unrelated-histories`), so `git log` shows
  Microsoft's original commits and new upstream changes can be merged.
- Roadmap and status: [`PLAN.md`](PLAN.md).

## License and authorship rules (mandatory)

- **Never remove or alter** Microsoft's copyright notices (`LICENSE`, `SPDX` headers, `ThirdPartyNotices.md`,
  `packages/markitdown-ocr/LICENSE`).
- **New** fork files may carry: `# SPDX-FileCopyrightText: 2026 Jorge Cañas` + `# SPDX-License-Identifier: MIT`.
- **Modified** upstream files: keep the original header; any added line is additional, never a replacement.
- Do not use Microsoft trademarks/logos in a way that implies official endorsement.
- It is fine (and expected) to state that work is done with Claude Code: commits carry `Co-Authored-By: Claude ...`.

## Spec-driven development (OpenSpec)

OpenSpec (`@fission-ai/openspec`, installed globally via npm, v1.3.1) drives every feature/change.
Project config with context and per-artifact rules: [`openspec/config.yaml`](openspec/config.yaml).

| Command | When to use |
|---|---|
| `/opsx:explore` | Think through a problem or clarify requirements. Writes nothing — safe on `main`. |
| `/opsx:propose <change-id>` | Create a change: `proposal.md`, `design.md`, `specs/`, `tasks.md`. |
| `/opsx:apply` | Implement the tasks of a change. |
| `/opsx:archive` | Sync delta specs into `openspec/specs/`, archive the change, PR + merge to `main`. |

### Change id convention

`mkNNN-<kebab-case-name>` — `NNN` is the next zero-padded number. Find the highest existing one in
`openspec/changes/` and `openspec/changes/archive/` (archived folders are `<date>-mkNNN-...`).
Example: `mk001-pdf-noise-cleanup`. The same id names the branch, the change folder and the commit scope.

### Branch-per-change rule (critical)

Every change lives on its own branch; nothing from a change lands on `main` directly.

1. Pick the `<change-id>` **before** running any OpenSpec command that writes.
2. `git checkout main && git pull && git checkout -b feature/<change-id>`
3. `/opsx:propose <change-id>` (always pass the id explicitly) → commit
   `chore(<change-id>): add openspec artifacts`.
4. `/opsx:apply` → implementation commits on the same branch, e.g. `feat(<change-id>): ...`,
   `test(<change-id>): ...`. Push the branch as a safety net.
5. `/opsx:archive` → archive the change, then
   `gh pr create --base main --head feature/<change-id>` and `gh pr merge --merge --delete-branch`,
   then `git checkout main && git pull`.

- `gh` default repo is set to `jorcanha/markitdown` (`gh repo set-default`). **Never open PRs or issues against
  `microsoft/markitdown`.**
- Non-spec maintenance (tooling, docs, upstream syncs) uses `chore/<short-name>` branches with the same PR + merge flow.
- If the scope of a request is unclear, ask clarifying questions before `/opsx:propose`.

## Git

- Remotes: `origin` = owner's fork (push here). `upstream` = `https://github.com/microsoft/markitdown.git` (read-only).
- Sync with upstream on a `chore/upstream-sync-<date>` branch: `git fetch upstream && git merge upstream/main`.
- A pristine local clone of upstream lives at `C:\Users\jorge\Documents\github\_markdown\markitdown` — reference only, **do not edit**.

## CI (GitHub Actions) — disabled for now

- Upstream workflows were moved from `.github/workflows/` to `.github/workflows-disabled/` (`tests.yml`, `pre-commit.yml`),
  so GitHub does not run them. To re-enable: `git mv .github/workflows-disabled .github/workflows`
  (fix the Windows test issues below first, and consider adding a Windows job).
- Dependabot is disabled too: its config was moved to `.github/workflows-disabled/dependabot.yml` (restore it to
  `.github/dependabot.yml` when re-enabling CI). Its first run opened PRs #1/#2, which were closed.
- Before disabling, upstream's `tests` and `pre-commit` workflows **passed on Linux** (ubuntu-latest) in those PRs,
  confirming that the local test failures listed below are Windows-specific.

## Development environment (Windows 11, Python 3.13, uv)

```powershell
uv venv --python 3.13 .venv
uv pip install --python .venv -e "packages/markitdown[all]" pytest openai
.venv\Scripts\Activate.ps1          # needed: CLI tests spawn "python"
python -m pytest packages/markitdown/tests -q
markitdown file.pdf -o output.md
```

- Upstream uses `hatch` (`cd packages/markitdown && hatch test`); uv + pytest works the same.
- Formatting: `black` (see `.pre-commit-config.yaml`). Run `pre-commit run --all-files` or `black packages/` before committing.
- Network tests (YouTube, remote Wikipedia…) are skipped when `GITHUB_ACTIONS` is set (see `skip_remote` in `tests/test_module_vectors.py`).
- Shells: the Bash tool is Git Bash (`/c/Users/...`); PowerShell is also available.
- **Windows baseline (2026-11-13, `GITHUB_ACTIONS=1`)**: 138 passed, 33 skipped, 41 failed. The 41 failures are environmental:
  - 40 CLI tests (`test_cli_*.py`) run `subprocess.run(["python", "-m", "markitdown", ...])`; on Windows `python` resolves to the
    **base** interpreter (the venv `python.exe` is a launcher), which lacks the package → "No module named markitdown".
    Pending fix: use `sys.executable` in the tests.
  - `test_module_misc.py::test_file_uris` expects POSIX paths (`/path/to/file.txt`) but gets `C:\path\to\file.txt` on Windows.
  - Without `GITHUB_ACTIONS`, network tests and `test_speech_transcription` (needs `ffmpeg`) also fail.

## Architecture (`packages/markitdown/src/markitdown/`)

Monorepo with 4 packages in `packages/`:

| Package | Purpose |
|---|---|
| `markitdown` | Main library + CLI. |
| `markitdown-mcp` | MCP server with a single tool `convert_to_markdown(uri)` (STDIO / HTTP / SSE). Useful to plug into Claude. |
| `markitdown-ocr` | Plugin: OCR of embedded images (PDF/DOCX/PPTX/XLSX) via a vision LLM (`llm_client`). Registers at priority `-1.0` to replace built-in converters. |
| `markitdown-sample-plugin` | Example plugin (RTF). Template for custom plugins. |

Conversion flow (`_markitdown.py`):

1. `MarkItDown.convert(source)` dispatches by type: `convert_local` (path), `convert_uri` (`http/https/file/data:`), `convert_response`, `convert_stream`.
2. `_get_stream_info_guesses()` builds `StreamInfo` candidates (mimetype, extension, charset) from the extension + **magika** (content sniffing) + `charset_normalizer`.
3. `_convert()` iterates every guess × every converter sorted by `priority` (lower runs first; specific formats `0.0`, generic `10.0`).
   The first converter whose `accepts()` is True and whose `convert()` does not raise wins.
4. Final normalization: `rstrip` each line and collapse 3+ newlines into 2.

- Converter contract: `DocumentConverter.accepts(stream, info, **kw)` **must not move** the stream position (asserted);
  `convert()` returns `DocumentConverterResult(markdown, title)`.
- Converters live in `converters/` and are registered in `MarkItDown.enable_builtins()` (with equal priority, the last registered is tried first).
- Optional dependencies per format (`[pdf]`, `[docx]`…); if missing, the converter raises `MissingDependencyException` on convert.
- Plugins: entry point group `markitdown.plugin` exposing `register_converters(markitdown, **kwargs)`; only active with
  `enable_plugins=True` / `--use-plugins`.

### PDF converter (`converters/_pdf_converter.py`) — the most relevant one for this fork

- Uses **pdfplumber** per page: `_extract_form_content_from_words()` tries to detect borderless tables/forms from word positions;
  otherwise `page.extract_text()`.
- If **no** page is a form, it discards that and re-extracts the whole document with **pdfminer** (`extract_text`) → better spacing
  for prose, but the PDF is parsed twice.
- Post-processing: `_merge_partial_numbering_lines` (MasterFormat-style `.1`, `.2` numbering).
- Known limitations (improvement opportunities, see `PLAN.md`):
  - Output is mostly **plain text**: no headings (`#`), bold or list detection.
  - Repeated page headers/footers and page numbers are kept → wasted tokens.
  - End-of-line hyphenation and hard-wrapped paragraphs are not rejoined.
  - No page markers (useful to cite "page N").
  - Scanned PDFs → empty output unless the OCR plugin (vision LLM, costs tokens) or Azure Document Intelligence is used.
  - `_extract_tables_from_words()` is **dead code** (never called).

## Change conventions

- Prefer **opt-in** changes (new flags/parameters whose defaults keep upstream behavior) to ease future upstream merges and keep tests green.
- Every behavior change ships with a test in `packages/markitdown/tests/` (fixtures in `tests/test_files/`).
- Measure token impact: compare output size (characters / approx. tokens ≈ chars/4) before and after on a sample PDF.
- Never commit personal or confidential PDFs (the repo is public). Use `/output/` (git-ignored) for local experiments.

## Decision log

- 2026-11-13: Fork created from the local upstream clone (commit `a51f725`, version `0.1.6b2`). LICENSE with dual copyright
  (Microsoft + Jorge Cañas). README with fork notice. `.gitignore` = GitHub Python template + upstream entries + `/output/`.
- 2026-11-13: OpenSpec initialized (Claude Code skills/commands in `.claude/`). Change ids `mkNNN-<name>`, branch per change
  (`feature/<change-id>`), merge to `main` via PR at archive time. All repo content in English. GitHub Actions disabled
  (workflows and Dependabot config moved to `.github/workflows-disabled/`). `gh` default repo pinned to the fork.
