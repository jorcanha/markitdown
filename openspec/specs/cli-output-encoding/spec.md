# cli-output-encoding Specification

## Purpose
TBD - created by archiving change mk001-windows-test-fixes. Update Purpose after archive.

## Requirements

### Requirement: Redirected stdout is UTF-8
The CLI SHALL write the converted Markdown to stdout as UTF-8 bytes whenever stdout is not an interactive terminal (piped or redirected) and no `PYTHONIOENCODING` is set, regardless of the operating system's console code page or locale encoding, and SHALL NOT replace or drop any character of the converted Markdown.

#### Scenario: Process output with a legacy locale encoding
- **WHEN** the CLI prints the Markdown `José | 名前 | → ✓` to a non-terminal stdout whose default encoding is cp1252
- **THEN** the bytes written decode as UTF-8 to exactly `José | 名前 | → ✓` followed by a newline

#### Scenario: Redirecting to a file from a byte-preserving shell on Windows
- **WHEN** the user runs `markitdown tests/test_files/test_mskanji.csv > out.md` in cmd.exe, Git Bash or PowerShell 7.4+ on Windows with ANSI code page 1252 and neither `PYTHONUTF8` nor `PYTHONIOENCODING` set
- **THEN** `out.md` is valid UTF-8 and contains the line `| 名前 | 年齢 | 住所 |`

#### Scenario: Captured by a parent process
- **WHEN** a parent process runs the CLI on `json_late_non_ascii.json` with stdout captured through a pipe and neither `PYTHONUTF8` nor `PYTHONIOENCODING` set
- **THEN** the exit status is 0 and the captured bytes decode as UTF-8 to a text containing `"notes": "Late Unicode: café, 日本語, 😀"`

#### Scenario: POSIX behavior unchanged
- **WHEN** the CLI converts `test_mskanji.csv` on Linux with a UTF-8 locale and stdout redirected to a file
- **THEN** the file's bytes are identical to those produced by the CLI before this change

### Requirement: Explicit PYTHONIOENCODING is honored
The CLI SHALL NOT change the stdout encoding when the `PYTHONIOENCODING` environment variable is set to a non-empty value.

#### Scenario: User forces a legacy encoding
- **WHEN** `PYTHONIOENCODING=cp1252` is set and the CLI prints `José | 名前 | → ✓` to a non-terminal stdout
- **THEN** the bytes written are the cp1252 encoding of `José | ?? | ? ?` followed by a newline

### Requirement: Interactive terminal output stays graceful
The CLI SHALL keep the terminal's own encoding when stdout is an interactive terminal and SHALL replace characters that the terminal cannot represent instead of raising an encoding error.

#### Scenario: Terminal that cannot represent a character
- **WHEN** the CLI prints `José | 名前 | → ✓` to an interactive terminal whose encoding is ASCII
- **THEN** no exception is raised and the bytes written are `Jos? | ?? | ? ?` followed by a newline

### Requirement: Output file is UTF-8
The CLI SHALL write the converted Markdown as UTF-8 to the file given with `-o/--output`, independently of the shell, console code page and `PYTHONIOENCODING`.

#### Scenario: Writing CJK text to an output file
- **WHEN** the user runs `markitdown tests/test_files/test_mskanji.csv -o out.md` in any shell, including Windows PowerShell 5.1
- **THEN** reading `out.md` as UTF-8 yields a text containing `| 名前 | 年齢 | 住所 |`

### Requirement: Shell re-encoding is documented
The project documentation SHALL state that shells which re-encode a native command's output (Windows PowerShell 5.1 redirection, PowerShell pipelines into cmdlets or variables) can corrupt non-ASCII Markdown, and SHALL recommend `-o/--output` as the shell-independent way to obtain UTF-8.

#### Scenario: Agent guide covers the limitation
- **WHEN** a contributor reads the development notes in `CLAUDE.md`
- **THEN** they find the recommendation to use `markitdown <file> -o <out.md>` instead of `>` in PowerShell
