## ADDED Requirements

### Requirement: Redirected stdout is UTF-8
The CLI SHALL encode the converted Markdown written to stdout as UTF-8 whenever stdout is not an interactive terminal (piped or redirected to a file), regardless of the operating system's console code page or locale encoding, and SHALL NOT replace or drop any character of the converted Markdown.

#### Scenario: Redirecting a CSV with CJK text on Windows
- **WHEN** the user runs `markitdown tests/test_files/test_mskanji.csv > out.md` on Windows with a cp1252 console code page
- **THEN** `out.md` is valid UTF-8 and contains the line `| 名前 | 年齢 | 住所 |`

#### Scenario: Redirecting text with accents and symbols
- **WHEN** the user runs `markitdown sample.csv > out.md` where `sample.csv` contains `José,Bogotá,→ ✓ €`
- **THEN** `out.md` is valid UTF-8 and contains `| José | Bogotá | → ✓ € |` with no `?` or U+FFFD replacement characters

#### Scenario: Piping into another process
- **WHEN** a parent process runs the CLI with stdout captured through a pipe (e.g. `subprocess.run(..., capture_output=True)`)
- **THEN** the captured bytes decode as UTF-8 without errors

#### Scenario: POSIX behavior unchanged
- **WHEN** the CLI runs on Linux or macOS with a UTF-8 locale and stdout is redirected
- **THEN** the bytes written are identical to those produced before this change

### Requirement: Interactive terminal output stays graceful
When stdout is an interactive terminal, the CLI SHALL keep encoding the output with the terminal's encoding and
SHALL replace characters that the terminal cannot represent instead of raising an encoding error.

#### Scenario: Terminal that cannot represent a character
- **WHEN** the CLI prints Markdown containing a character unsupported by the terminal encoding to an interactive terminal
- **THEN** the CLI exits with status 0 and the unsupported character is shown as a replacement character

### Requirement: Output file is UTF-8
When the `-o/--output` option is given, the CLI SHALL write the converted Markdown to that file encoded as UTF-8.

#### Scenario: Writing CJK text to an output file
- **WHEN** the user runs `markitdown tests/test_files/test_mskanji.csv -o out.md`
- **THEN** reading `out.md` as UTF-8 yields a text containing `| 名前 | 年齢 | 住所 |`
