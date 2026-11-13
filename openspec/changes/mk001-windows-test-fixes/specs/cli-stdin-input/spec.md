## ADDED Requirements

### Requirement: Documents piped on stdin are converted
The CLI SHALL convert a document received on stdin when no filename argument is given, producing the same Markdown as converting the same bytes from a file path, on Windows and on POSIX, whether stdin is a pipe or a file redirection.

#### Scenario: Piping a PDF on Windows
- **WHEN** the user runs `cat tests/test_files/test.pdf | markitdown` on Windows
- **THEN** the exit status is 0 and stdout contains `While there is contemporaneous exploration of multi-agent approaches`

#### Scenario: Piping a text format on Windows
- **WHEN** the user runs `cat tests/test_files/test.json | markitdown` on Windows
- **THEN** the exit status is 0 and stdout contains `5b64c88c-b3c3-4510-bcb8-da0b200602d8` instead of being empty

#### Scenario: Piping a ZIP-based format without hints
- **WHEN** a parent process runs `markitdown` with the bytes of `tests/test_files/test.docx` as stdin and no `-x`, `-m` or `-c` hint
- **THEN** the exit status is 0 and stdout contains `314b0a30-5b04-470b-b9f7-eed2c2bec74a`

#### Scenario: File redirection keeps working
- **WHEN** the user runs `markitdown < tests/test_files/test.json`
- **THEN** the output is the same as for `markitdown tests/test_files/test.json`

### Requirement: Stdin failures are not silent
The CLI SHALL NOT exit with status 0 and empty output when stdin contained a document that the same CLI converts successfully from a file path.

#### Scenario: Every bundled test vector converts from stdin
- **WHEN** each local test vector of `GENERAL_TEST_VECTORS` is supplied to `markitdown` on stdin without a filename
- **THEN** every run exits with status 0 and its stdout contains all of that vector's `must_include` strings
