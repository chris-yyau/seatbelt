# Seatbelt Plugin

Zero-config security scanning for Claude Code. Runs 8 scanners as PreToolUse hooks before every `git commit`.

## Architecture

```
hooks/
  hooks.json              # Hook wiring (PreToolUse → scanners, PostToolUse → summary)
  scripts/
    scan-{scanner}.sh     # One scanner per file (gitleaks, checkov, trivy, zizmor, semgrep, shellcheck, commitlint, signing)
    scan-summary.sh       # PostToolUse aggregator
    lib/
      detect-commit.sh    # Shared: parses hook JSON stdin, sets IS_GIT_COMMIT
      config.sh           # Shared: loads .seatbelt.yml, sets SEATBELT_* vars
      block-emit.sh       # Shared: emits {"decision":"block"} JSON or stderr warning
      result-dir.sh       # Shared: repo-specific tmp dir for scanner results
      skip-audit.sh       # Shared: logs SKIP_* bypass events to .claude/bypass-log.jsonl
commands/
  scan.md                 # /seatbelt:scan command
  setup.md                # /seatbelt:setup command (health check + install; --check for read-only)
scripts/
  doctor.sh               # Health check script (JSON output)
  bump-version.sh         # Version sync across manifests
  check-required-checks.sh # Validates .github/required-checks.lock vs workflows + branch protection
tests/
  run-tests.sh            # Test runner with assertion helpers
  test-*.sh               # 18 test files, 141 assertions
  fixtures/               # JSON stubs and YAML config fixtures
```

## Scanner Pattern

Every scanner follows the same structure:

1. Check `SKIP_SEATBELT` / `SKIP_{SCANNER}` env vars
2. Source `lib/detect-commit.sh` — exit if not a git commit
3. Source `lib/result-dir.sh` — clean stale result file
4. Source `lib/config.sh` — load `.seatbelt.yml` settings
5. Check enabled flag — exit if disabled
6. Check scanner installed — fail-open with stderr warning if missing
7. Run scanner on staged content
8. Source `lib/block-emit.sh` — emit block decision if findings meet threshold
9. Write result file for summary aggregation

**Fail-open by default:** Missing scanners warn but don't block. Script errors trapped with `exit 0`.

**Strict mode:** `SEATBELT_STRICT=false` downgrades block decisions to stderr warnings.

## Configuration

Precedence: **env var > `.seatbelt.yml` > default**

Key env vars: `SKIP_SEATBELT=1`, `SKIP_{SCANNER}=1`, `SEATBELT_{SCANNER}_ENABLED`, `SEATBELT_STRICT`, `SEATBELT_{SCANNER}_SEVERITY`, `SEATBELT_{SCANNER}_TIMEOUT`

## Testing

```bash
bash tests/run-tests.sh          # Run all 141 tests
```

- Custom bash test harness in `run-tests.sh` with helpers: `assert_exit_0`, `assert_stdout_contains`, `assert_stdout_json_block`, etc.
- Each test file is `source`d by the runner (shares `PASS`/`FAIL` counters, assertion functions)
- Tests use fixture JSON files from `tests/fixtures/`
- `make_degraded_path()` creates a PATH without scanner binaries for testing fail-open behavior
- CI runs tests on both ubuntu-latest and macos-latest

## Version Sync

Version numbers are managed across three manifests (declared in `.version-bump.json`):

- `package.json` — `version` field
- `.claude-plugin/plugin.json` — `version` field
- `.claude-plugin/marketplace.json` — `metadata.version` field

**Automated (preferred):** semantic-release bumps all manifests via `@semantic-release/exec` → `bump-version.sh` on every merge to main. No manual version management needed.

**Drift detection:** `./scripts/bump-version.sh --check` runs in CI on PRs to catch version desync.

## CI/CD

| Workflow | Triggers | Purpose |
|----------|----------|---------|
| `tests.yml` | push/PR to main | Unit tests (matrix), shellcheck, integration tests, version-drift, commitlint |
| `security.yml` | push/PR (security-relevant paths) | gitleaks, shellcheck, trivy, semgrep, checkov, zizmor |
| `release.yml` | push to main | semantic-release + SLSA attestation |
| `scorecard.yml` | weekly cron | OpenSSF Scorecard |
| `pinact.yml` | push to main (workflow changes) | Auto-pin actions to SHA |
| `dependabot-auto-merge.yml` | Dependabot PRs | Approve + auto-merge safe patch/minor bumps (opt-in via `vars.DEPENDABOT_AUTO_APPROVE`) |
| `bypass-audit.yml` | daily cron + manual | Detect commits that reached `main` without a merged PR (admin-bypass audit); opens labeled `admin-bypass` issues |

## Conventions

- **Language:** Bash (POSIX-compatible where possible, `set -euo pipefail`)
- **Commits:** Conventional commits enforced by commitlint (`feat:`, `fix:`, `chore:`, etc.)
- **Actions:** All SHA-pinned with version comments, `persist-credentials: false`, `harden-runner` on every job
- **Dependencies:** Zero runtime deps. npm packages only for release automation (semantic-release via `npx`)
