# Linux verification — instructions for the second machine

Audience: any coding agent (or person) on a machine with **Podman** and **git**. You do not need Python on the host,
and you do not need to know the rest of the project. Read `AGENTS.md` at the repository root first for the house rules
(English only in the repo, branch per change, never push to `main`).

This file, `tasks.md`, `linux-verify.sh` and `AGENTS.md` exist only on branch `feature/mk001-windows-test-fixes`
until the change is merged. A fresh clone starts on `main`, where none of them is present: check out the branch first
(Step 0).

## What this is

The change `mk001-windows-test-fixes` makes the `markitdown` CLI write UTF-8 when its stdout is redirected or piped
(it used to write the Windows ANSI code page and lose characters). It was implemented and tested on Windows only.
Your job is to run it on Linux and **report** what happens. Tasks: group 7 in `tasks.md` (same folder).

## Rules

- **Report only.** Do not modify source code, tests or the script, even if something fails. Record the failure.
- Work on branch `feature/mk001-windows-test-fixes`. Never commit to `main`. Do not open or merge pull requests.
- The only files you create or change are `linux-verification-results.md` and the checkboxes of group 7 in `tasks.md`.
- Everything you write in the repository is in English.

## Which machine to use

Any machine that can run Linux containers. Nothing is installed on the host except the container runtime and git, and
the host's operating system does not influence the results: the container clones the repository itself.

| | Needed | Notes |
|---|---|---|
| Container runtime | Podman 4 or newer (Podman Desktop is fine) | Docker works too: replace `podman` with `docker` in every command and say so in the results. |
| Host OS | Linux, macOS or Windows | On macOS and Windows, Podman runs containers in a Linux virtual machine that must be running: `podman machine init` (once) and `podman machine start`. The host needs hardware virtualization enabled. |
| CPU architecture | x86_64 (amd64) preferred | It is the architecture of the development machine and of upstream CI. arm64 (Apple Silicon, ARM servers) has images too, but the Python dependencies were never installed there by this project: run it as it is, record the architecture, and if `RESULT INSTALL: FAIL` appears, record it and stop. Do not emulate another architecture. |
| Memory for containers | 4 GB or more | Run `podman info` and read `memTotal` and `cpus` under `host`. A Podman machine created with defaults may have only 2 GB: `podman machine stop`, `podman machine set --memory 4096`, `podman machine start`. With the WSL backend on Windows, memory is managed by WSL and this is not needed. |
| Free disk | about 3 GB | Two base images, plus the dependencies, which are downloaded once per run. Containers are removed afterwards (`--rm`). |
| Network | outbound HTTPS | `docker.io` (images), `deb.debian.org` (apt), `github.com` (clone), `pypi.org` and `files.pythonhosted.org` (pip). A proxy or an offline machine will not work without extra setup. |
| Time | 10–15 minutes per Python version | Estimate. The suite alone takes about 5 minutes on the Windows development machine. |
| GitHub access on the host | Permission to push to `jorcanha/markitdown`, and a git identity | Only Step 3 needs it. The container needs no credentials: the repository is public. |

The memory, disk and time figures are estimates from the Windows development machine (its virtual environment is
about 350 MB); they were not measured on Linux. If the machine is smaller, try anyway and record what happened.

## Step 0 — Preconditions

Container runtime:

```bash
podman --version
podman info                                   # must print host information without an error
podman run --rm docker.io/library/python:3.12-slim python -c "import platform; print(platform.platform())"
```

The last command proves that images can be pulled and containers can run, and prints the kernel and architecture
(for example `Linux-6.x-x86_64-with-glibc2.41`). Note it for the results file. If it fails, see "If something goes
wrong" before going on.

Repository:

```bash
git clone https://github.com/jorcanha/markitdown        # or: git fetch --all, in an existing clone
cd markitdown
git checkout feature/mk001-windows-test-fixes && git pull
git rev-parse HEAD                                      # the commit you are going to test; note it
grep -n "_should_force_utf8_stdout" packages/markitdown/src/markitdown/__main__.py
grep -n "Ready to run" openspec/changes/mk001-windows-test-fixes/tasks.md
grep -n "^- \[ \]" openspec/changes/mk001-windows-test-fixes/tasks.md
```

- If the first `grep` prints nothing, the fix has not been implemented and pushed yet (task groups 1–6). **Stop** and
  tell the owner.
- The second `grep` must print one line (group 7 says "Ready to run").
- The third `grep` must list only tasks 7.1, 7.2 and 7.3. If any task of groups 1–6 is listed, the development
  machine has not finished: **stop** and tell the owner.

Permission to publish the results (Step 3). Check it now, so that a run is not wasted:

```bash
git config user.name && git config user.email           # both must print a value
git push --dry-run origin feature/mk001-windows-test-fixes
```

`git push --dry-run` sends nothing; it must end with `Everything up-to-date` and without asking for a password or
printing `denied`. If it fails, sign in first (for example `gh auth login` with the GitHub CLI, or the credential
manager / SSH key that the machine already uses for GitHub) and set the identity with
`git config user.name "<name>"` and `git config user.email "<email>"`. If you cannot get push access, run the checks
anyway, write the results file, and give its content to the owner instead of pushing.

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

The two `.log` files are scratch output: do **not** commit them (`*.log` is git-ignored, so `git add` skips them;
delete them when you are done). Then look at the result lines:

```bash
grep -E "^(RESULT|commit:|base |Python|stdout encoding|LANG)|^[a-z_]+\.(csv|json): " linux-run-py312.log linux-run-py313.log
```

In PowerShell, where `grep` may not exist:

```powershell
Select-String -Path linux-run-py31*.log -Pattern '^(RESULT|commit:|base |Python|stdout encoding|LANG)|^[a-z_]+\.(csv|json): '
```

The `commit:` line of **both** logs must show the commit that `git rev-parse HEAD` printed in Step 0. If it shows a
different one, the branch moved in between: run `git pull` and repeat Step 1, so that the results describe one commit.

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
- Container platform (output of the `platform.platform()` command in Step 0):
- Resources for containers (`cpus` and `memTotal` from `podman info`):
- `podman --version` (or `docker --version`):
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
| `podman info` or `podman run` cannot connect | On macOS and Windows the Podman machine is not running: `podman machine start` (after `podman machine init` the first time). On Linux, check that the user can run rootless containers (`podman run --rm docker.io/library/hello-world`). |
| The run ends with `Killed` or exit status 137 | The container ran out of memory. Give the Podman machine at least 4 GB (see "Which machine to use") and repeat the run. Record that it happened. |
| `No space left on device` | Free disk space is insufficient. Do not delete images or containers that are not yours; tell the owner how much space is free (`podman system df`) and stop. |
| `RESULT PRECONDITION: FAIL` | The implementation is not pushed yet. Stop; nothing to record. |
| `apt-get` or `git clone` fails | Network or registry problem on the host. Retry once; if it persists, record the error text under "Deviations" and stop. |
| `RESULT INSTALL: FAIL` | Record the last 30 lines of the log. Do not try other package versions. |
| The script stops with a shell error | Record the error line and the 20 lines before it. Do not edit the script. |
| Image cannot be pulled | Try `podman pull docker.io/library/python:3.12-slim` separately and record its error. |
| `git push` is rejected | `git pull --rebase origin feature/mk001-windows-test-fixes`, then push again. Never force-push. |
