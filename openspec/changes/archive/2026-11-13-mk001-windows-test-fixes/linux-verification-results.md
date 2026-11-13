# Linux verification results — mk001-windows-test-fixes

- Date (UTC): 2026-11-13 20:46 UTC (Python 3.12 run); Python 3.13 run same day
- Run by (agent / person): CODA (coding agent), at the owner's request
- Host OS and architecture: Windows 11 x86_64 (Podman machine on WSL2)
- Container platform (output of the `platform.platform()` command in Step 0): `Linux-6.18.33.2-microsoft-standard-WSL2-x86_64-with-glibc2.41`
- Resources for containers (`cpus` and `memTotal` from `podman info`): cpus=14, memTotal=16481660928 (~15.3 GB)
- `podman --version` (or `docker --version`): podman version 5.8.3
- Tested commit (the `commit:` line printed by the script): 695e113da4a36d3dbeb156024355866517cc38af on feature/mk001-windows-test-fixes

## Python 3.12 (`docker.io/library/python:3.12-slim`)

- Exit status: 0
- Environment lines (`Python`, `LANG`, `stdout encoding`):

    Python 3.12.16
    LANG=C.UTF-8 LC_ALL=<unset>
    stdout encoding: utf-8 | preferred encoding: UTF-8

    RESULT PRECONDITION: PASS
    RESULT INSTALL: PASS - markitdown 0.1.9
    RESULT A: PASS - 1129 passed, 61 skipped, 7 warnings in 240.10s (0:04:00)
    RESULT B: PASS - without the fix exactly the expected test fails (test_redirected_stdout_is_utf8_even_with_legacy_locale) - 1 failed, 3 passed, 24 deselected in 1.91s
    RESULT C: PASS - output identical to the base commit and valid UTF-8 for both samples
    RESULT WORKTREE: PASS - clean, every touched file was restored

- Per-sample lines of check C (`test_mskanji.csv: ...`, `json_late_non_ascii.json: ...`):

    test_mskanji.csv: fixed=74a566488c88a1da043cb75a0538083e7ec8ab591b8ba1d51eb04ec79fd15e1f base=74a566488c88a1da043cb75a0538083e7ec8ab591b8ba1d51eb04ec79fd15e1f valid-utf8 (142 bytes)
    json_late_non_ascii.json: fixed=56168f91b1583917d6189a7595891179bd9044e7bd8be55107654e4b7f093ab2 base=56168f91b1583917d6189a7595891179bd9044e7bd8be55107654e4b7f093ab2 valid-utf8 (10803 bytes)

## Python 3.13 (`docker.io/library/python:3.13-slim`)

- Exit status: 0
- Environment lines (`Python`, `LANG`, `stdout encoding`):

    Python 3.13.18
    LANG=C.UTF-8 LC_ALL=<unset>
    stdout encoding: utf-8 | preferred encoding: UTF-8

    RESULT PRECONDITION: PASS
    RESULT INSTALL: PASS - markitdown 0.1.9
    RESULT A: PASS - 1129 passed, 61 skipped, 7 warnings in 191.42s (0:03:11)
    RESULT B: PASS - without the fix exactly the expected test fails (test_redirected_stdout_is_utf8_even_with_legacy_locale) - 1 failed, 3 passed, 24 deselected in 6.17s
    RESULT C: PASS - output identical to the base commit and valid UTF-8 for both samples
    RESULT WORKTREE: PASS - clean, every touched file was restored

- Per-sample lines of check C (`test_mskanji.csv: ...`, `json_late_non_ascii.json: ...`):

    test_mskanji.csv: fixed=74a566488c88a1da043cb75a0538083e7ec8ab591b8ba1d51eb04ec79fd15e1f base=74a566488c88a1da043cb75a0538083e7ec8ab591b8ba1d51eb04ec79fd15e1f valid-utf8 (142 bytes)
    json_late_non_ascii.json: fixed=56168f91b1583917d6189a7595891179bd9044e7bd8be55107654e4b7f093ab2 base=56168f91b1583917d6189a7595891179bd9044e7bd8be55107654e4b7f093ab2 valid-utf8 (10803 bytes)

## Deviations and notes

(None. Both runs matched the expected results exactly: all six checks passed on both Python versions, exit status 0,
and the tested commit is the branch tip (695e113) in both logs. The only difference from the Windows baseline is the
skip count (61 skipped on Linux vs 49 on Windows), which the instructions anticipated as platform-specific and
irrelevant — only `failed` / `error` matter for check A.)

## Verdict

All checks passed on both versions.
