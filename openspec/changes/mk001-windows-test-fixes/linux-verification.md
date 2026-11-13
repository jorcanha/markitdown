# Linux verification — instructions for the second machine

Audience: any coding agent (or person) on a machine with **Podman** and **git**. You do not need Python on the host,
and you do not need to know the rest of the project. Read `AGENTS.md` at the repository root first for the house rules
(English only in the repo, branch per change, never push to `main`).

## What this is

The change `mk001-windows-test-fixes` makes the `markitdown` CLI write UTF-8 when its stdout is redirected or piped
(it used to write the Windows ANSI code page and lose characters). It was implemented and tested on Windows only.
Your job is to run it on Linux and **report** what happens. Tasks: group 7 in `tasks.md` (same folder).

## Rules

- **Report only.** Do not modify source code, tests or the script, even if something fails. Record the failure.
- Work on branch `feature/mk001-windows-test-fixes`. Never commit to `main`. Do not open or merge pull requests.
- The only files you create or change are `linux-verification-results.md` and the checkboxes of group 7 in `tasks.md`.
- Everything you write in the repository is in English.

## Step 0 — Preconditions

```bash
podman --version
git clone https://github.com/jorcanha/markitdown        # or: git fetch --all, in an existing clone
cd markitdown
git checkout feature/mk001-windows-test-fixes && git pull
grep -n "_should_force_utf8_stdout" packages/markitdown/src/markitdown/__main__.py
```

If `grep` prints nothing, the fix has not been implemented and pushed yet (task groups 1–6). **Stop** and tell the owner.

## Step 1 — Run the checks (two Python versions)

The container clones the public repository itself. Nothing is mounted from the host, so the command is identical in
bash, zsh and PowerShell, on Linux, macOS and Windows hosts. Be patient: on the Windows development machine the test
suite alone took about 5 minutes, plus the time `pip` needs to download the dependencies.

```bash
podman run --rm docker.io/library/python:3.12-slim bash -c "apt-get update -qq && apt-get install -y -qq git > /dev/null && git clone -q --branch feature/mk001-windows-test-fixes https://github.com/jorcanha/markitdown /work && cd /work && bash openspec/changes/mk001-windows-test-fixes/linux-verify.sh" > linux-run-py312.log 2>&1
echo "exit status: $?"        # PowerShell: $LASTEXITCODE

podman run --rm docker.io/library/python:3.13-slim bash -c "apt-get update -qq && apt-get install -y -qq git > /dev/null && git clone -q --branch feature/mk001-windows-test-fixes https://github.com/jorcanha/markitdown /work && cd /work && bash openspec/changes/mk001-windows-test-fixes/linux-verify.sh" > linux-run-py313.log 2>&1
echo "exit status: $?"
```

The two `.log` files are scratch output: do **not** commit them (delete them, or keep them outside the repository).
Then look at the result lines:

```bash
grep -E "^(RESULT|commit:|base |Python|stdout encoding|LANG)|^[a-z_]+\.(csv|json): " linux-run-py312.log linux-run-py313.log
```

## What the script checks

| Check | What it does | Passes when |
|---|---|---|
| PRECONDITION | Looks for the fix in `__main__.py`. | The helper `_should_force_utf8_stdout` exists. |
| INSTALL | `pip install -e "packages/markitdown[all]" pytest openai pyyaml` in a fresh venv. | pip succeeds. |
| A | Full `packages/markitdown/tests` suite, network tests skipped. | The pytest summary has `passed` and no `failed` / `error`. |
| B | Restores `__main__.py` from the base commit (no fix), runs the four new stdout tests, puts the fix back. | Exactly one test fails: `test_redirected_stdout_is_utf8_even_with_legacy_locale`. This proves the tests protect the fix on Linux too. |
| C | Converts two sample files with stdout redirected, with and without the fix, and compares SHA-256. | Hashes are identical and the output is valid UTF-8: the fix changes nothing on Linux. |
| WORKTREE | `git status` inside the container. | Clean: every file the script touched was restored. |

Exit status: `0` all checks passed · `1` at least one check failed or was unexpected · `2` precondition failed ·
`3` install failed.

**How sure are the expectations?** The script's mechanics were dry-run on Windows (Git Bash, scratch clone with the fix
applied): PRECONDITION, INSTALL, A (`1140 passed, 49 skipped`) and WORKTREE passed there. On Windows, B reported two
failing tests and C reported different hashes — correct for Windows, where the defect exists. The Linux expectations
for **B and C come from analysis and have never been observed.** If they differ, that is a finding, not your mistake:
record it exactly.

The number of passed/skipped tests on Linux may differ from Windows (platform-specific skips). Only `failed` and
`error` matter for check A.

## Step 2 — Record the results

Create `openspec/changes/mk001-windows-test-fixes/linux-verification-results.md` from this template. Copy the lines
from the logs verbatim; do not summarize or "fix" them.

```markdown
# Linux verification results — mk001-windows-test-fixes

- Date (UTC):
- Run by (agent / person):
- Host OS and architecture:
- `podman --version`:
- Tested commit (the `commit:` line printed by the script):

## Python 3.12 (`docker.io/library/python:3.12-slim`)

- Exit status:
- Environment lines (`Python`, `LANG`, `stdout encoding`):

    RESULT PRECONDITION: ...
    RESULT INSTALL: ...
    RESULT A: ...
    RESULT B: ...
    RESULT C: ...
    RESULT WORKTREE: ...

- Per-sample lines of check C (`test_mskanji.csv: ...`, `json_late_non_ascii.json: ...`):

## Python 3.13 (`docker.io/library/python:3.13-slim`)

(same fields)

## Deviations and notes

(Anything that did not match the expected results, any error of the script itself with the relevant log excerpt,
anything you had to do differently. Write "None" if there is nothing.)

## Verdict

(One line: "All checks passed on both versions" or "Not all checks passed — see deviations".)
```

## Step 3 — Publish

```bash
# on branch feature/mk001-windows-test-fixes, in the repository clone on the host
# tick tasks 7.1 and 7.2 in openspec/changes/mk001-windows-test-fixes/tasks.md ("- [ ]" -> "- [x]")
git add openspec/changes/mk001-windows-test-fixes/linux-verification-results.md openspec/changes/mk001-windows-test-fixes/tasks.md
git status --short            # must list only those two files
git commit -m "test(mk001-windows-test-fixes): record Linux verification results"
git push origin feature/mk001-windows-test-fixes
```

Tick 7.1 and 7.2 even if a check failed — the task is "run and record", and the verdict line says how it went.
Leave task 7.3 unticked: the owner does it on the development machine.

## If something goes wrong

| Problem | What to do |
|---|---|
| `RESULT PRECONDITION: FAIL` | The implementation is not pushed yet. Stop; nothing to record. |
| `apt-get` or `git clone` fails | Network or registry problem on the host. Retry once; if it persists, record the error text under "Deviations" and stop. |
| `RESULT INSTALL: FAIL` | Record the last 30 lines of the log. Do not try other package versions. |
| The script stops with a shell error | Record the error line and the 20 lines before it. Do not edit the script. |
| Image cannot be pulled | Try `podman pull docker.io/library/python:3.12-slim` separately and record its error. |
| `git push` is rejected | `git pull --rebase origin feature/mk001-windows-test-fixes`, then push again. Never force-push. |
