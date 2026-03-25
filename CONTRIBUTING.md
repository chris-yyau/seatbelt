# Contributing to Seatbelt

Thanks for your interest in contributing to Seatbelt! This guide covers how to set up a development environment, run tests, and submit changes.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/chris-yyau/seatbelt.git
   cd seatbelt
   ```

2. Install development dependencies:
   ```bash
   # ShellCheck for linting (required for CI)
   brew install shellcheck    # macOS
   # apt-get install shellcheck  # Linux

   # Commitlint for commit message validation (required for PRs)
   npm install @commitlint/cli @commitlint/config-conventional
   ```

3. Optionally install scanner binaries for manual testing:
   ```bash
   brew install gitleaks checkov trivy zizmor shellcheck
   pip3 install semgrep
   ```

## Project Structure

```text
seatbelt/
├── hooks/scripts/         # Scanner hook scripts (PreToolUse + PostToolUse)
│   ├── lib/               # Shared libraries
│   │   ├── detect-commit.sh   # Git commit detection from hook JSON
│   │   ├── result-dir.sh     # Temp result directory management
│   │   └── config.sh         # .seatbelt.yml config loader
│   ├── scan-gitleaks.sh   # Secret scanning (BLOCK)
│   ├── scan-checkov.sh    # IaC scanning (BLOCK)
│   ├── scan-trivy.sh      # Dependency CVE scanning (warn)
│   ├── scan-zizmor.sh     # GitHub Actions scanning (warn)
│   ├── scan-semgrep.sh    # Source code security scanning (warn)
│   ├── scan-shellcheck.sh # Shell script quality scanning (warn)
│   ├── scan-commitlint.sh # Commit message format validation (advisory)
│   ├── scan-signing.sh    # Commit signing reminder (advisory)
│   └── scan-summary.sh    # PostToolUse aggregate summary
├── scripts/
│   └── doctor.sh          # Health check and diagnostics
├── commands/              # Claude Code slash commands
│   ├── setup.md           # /seatbelt:setup
│   ├── doctor.md          # /seatbelt:doctor
│   └── scan.md            # /seatbelt:scan
├── tests/                 # Test suite (bash-based)
│   ├── run-tests.sh       # Test runner
│   ├── fixtures/          # Test fixture files
│   └── test-*.sh          # Individual test files
└── .claude-plugin/
    └── plugin.json        # Plugin manifest
```

## Running Tests

```bash
# Run the full test suite
bash tests/run-tests.sh

# Run ShellCheck linting
shellcheck hooks/scripts/scan-*.sh hooks/scripts/lib/*.sh scripts/doctor.sh
```

All tests are pure bash — no external test framework required. The test suite mocks scanner binaries so you don't need them installed to run tests.

## Writing Tests

Tests live in `tests/test-*.sh`. Each file is sourced by `run-tests.sh`. Use the helpers defined in the runner:

```bash
# Tests use run_hook_test which captures STDOUT, STDERR, and EXIT_CODE,
# then you assert against those variables:

assert_exit_0                        # Expected exit code 0
assert_stdout_empty                  # No stdout output
assert_stdout_contains "SEATBELT"    # Stdout includes string
assert_stderr_contains "DEGRADED"    # Stderr includes string
assert_stdout_json_block             # Stdout contains {"decision":"block"}
assert_stdout_no_block               # Stdout does NOT contain block decision
```

Every scanner hook has a corresponding test file. When adding a feature or fixing a bug, add tests that cover both the happy path and edge cases.

## Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/). PRs are validated by commitlint in CI.

```text
feat: add support for new scanner
fix: handle empty staged file list
refactor: extract shared JSON parsing
test: add edge case for trivy DB missing
docs: update README with new examples
chore: bump CI action versions
```

## Pull Request Process

1. Create a feature branch from `main`
2. Make your changes with tests
3. Ensure all checks pass locally:
   ```bash
   bash tests/run-tests.sh
   shellcheck hooks/scripts/scan-*.sh hooks/scripts/lib/*.sh scripts/doctor.sh
   ```
4. Open a PR against `main`
5. CI runs: tests, shellcheck, and commitlint

## Adding a New Scanner

To add a new scanner hook:

1. Create `hooks/scripts/scan-<name>.sh` following the existing pattern:
   - Source `lib/detect-commit.sh` for commit detection
   - Source `lib/config.sh` for `.seatbelt.yml` config support
   - Check `SKIP_<NAME>` and `SKIP_SEATBELT` env vars
   - Handle missing binary gracefully (degraded mode)
   - Use `BLOCK` or `warn` fail mode consistently
   - Write warn findings to `$SEATBELT_RESULT_DIR/<name>` for the summary

2. Register the hook in `hooks/hooks.json` (add a PreToolUse entry matching the existing scanner pattern)

3. Add tests in `tests/test-<name>.sh` covering:
   - Skips non-commit commands
   - Skips when `SKIP_<NAME>=1`
   - Skips when `SKIP_SEATBELT=1`
   - Degraded mode when binary not installed
   - Detection of findings
   - Clean scan (no findings)

4. Update `README.md` scanner table and supported file types

5. Update `scripts/doctor.sh` to detect the new scanner

## Code Style

- Shell scripts target **bash 3.2+** (macOS default)
- All scripts pass **ShellCheck** with zero warnings
- Use `# shellcheck disable=SC1091` for dynamically resolved `source` paths
- Quote all variables: `"$var"` not `$var`
- Use `[[ ]]` for conditionals in bash, `[ ]` for POSIX compatibility

## Security

If you discover a security vulnerability, please see [SECURITY.md](SECURITY.md) for responsible disclosure instructions.
