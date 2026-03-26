# Seatbelt

[![CI](https://github.com/chris-yyau/seatbelt/actions/workflows/tests.yml/badge.svg)](https://github.com/chris-yyau/seatbelt/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/chris-yyau/seatbelt/badge)](https://scorecard.dev/viewer/?uri=github.com/chris-yyau/seatbelt)

Zero-config security scanning for vibe coders. Seatbelt is a [Claude Code plugin](https://docs.anthropic.com/en/docs/claude-code/plugins) that automatically scans your staged changes before every `git commit`.

## What it does

Seatbelt intercepts `git commit` commands and runs eight security scanners on your staged changes:

| Scanner | What it checks | Fail mode |
|---------|---------------|-----------|
| **gitleaks** | Hardcoded secrets, API keys, credentials | BLOCK — commit is prevented |
| **checkov** | IaC misconfigurations (Dockerfile, Terraform, k8s, Helm, GitHub Actions, docker-compose) | BLOCK — commit is prevented |
| **trivy** | Dependency CVEs in lock files (HIGH/CRITICAL severity) | warn — findings shown, commit allowed |
| **zizmor** | GitHub Actions workflow security issues (injection, unpinned actions) | warn — findings shown, commit allowed |
| **semgrep** | Code-level security bugs (SQL injection, XSS, command injection) | warn — findings shown, commit allowed |
| **shellcheck** | Shell script quality and correctness issues | warn — findings shown, commit allowed |
| **commitlint** | Conventional commit message format (advisory) | warn — findings shown, commit allowed |
| **signing** | Commit signing reminder (advisory) | warn — findings shown, commit allowed |

You don't need all eight installed. Scanners that aren't found are skipped with a warning like:

```
SEATBELT DEGRADED: gitleaks not installed — secret scanning DISABLED (brew install gitleaks | /seatbelt:doctor)
```

Install any combination you want — Seatbelt works with one scanner or all eight.

## Install

Add the marketplace and install the plugin, then let seatbelt guide you through scanner setup:

```bash
claude plugin marketplace add chris-yyau/seatbelt
claude plugin install seatbelt@seatbelt
```

Then run setup inside Claude Code:

```
/seatbelt:setup
```

`/seatbelt:setup` detects what's missing, proposes install commands grouped by package manager, asks for your confirmation, then runs smoke tests to verify everything works.

### Manual Install

If you prefer to install scanner binaries yourself:

```bash
# macOS (recommended: install all)
brew install gitleaks checkov trivy zizmor semgrep shellcheck

# Linux (brew if available, otherwise pip3/releases)
brew install gitleaks checkov trivy zizmor semgrep shellcheck
# Or without brew:
#   gitleaks:   https://github.com/gitleaks/gitleaks/releases
#   trivy:      https://aquasecurity.github.io/trivy/latest/getting-started/installation/
#   checkov:    pip3 install checkov
#   zizmor:     pip3 install zizmor (or cargo install zizmor)
#   semgrep:    pip3 install semgrep
#   shellcheck: https://github.com/koalaman/shellcheck/releases
```

## How it works

Seatbelt registers [PreToolUse hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) on the Bash tool. Each hook checks if the command is a `git commit` and exits immediately if not — non-commit commands have near-zero overhead.

When a `git commit` is detected, seatbelt uses two approaches to scan staged content:

- **gitleaks** reads the git staging area directly via its `--staged` flag
- **checkov, trivy, zizmor, semgrep, shellcheck** extract staged file content to a temp directory via `git show`, then scan the extracted files. This ensures scanners see exactly what will be committed, not the current working tree.
- **commitlint** validates the commit message format against conventional commit rules
- **signing** checks whether `commit.gpgsign` is configured in git

All eight scanner hooks share a common commit-detection library (`hooks/scripts/lib/detect-commit.sh`) that parses Claude Code's hook input JSON to determine if the command is a `git commit`. Non-commit commands are ignored with near-zero overhead.

If you use partial staging (`git add -p`), seatbelt scans exactly the hunks you staged.

### Architecture

```
Claude Code                        Seatbelt Plugin
───────────                        ───────────────

  git commit ──► PreToolUse hooks fire (parallel)
                    │
                    ├─► scan-gitleaks.sh ──► gitleaks protect --staged
                    │     └─► BLOCK on secrets found
                    │
                    ├─► scan-checkov.sh  ──► extract staged IaC ──► checkov
                    │     └─► BLOCK on misconfigurations
                    │
                    ├─► scan-trivy.sh   ──► extract staged locks ──► trivy fs
                    │     └─► WARN on CVEs (commit proceeds)
                    │
                    ├─► scan-zizmor.sh  ──► extract staged workflows ──► zizmor
                    │     └─► WARN on workflow issues (commit proceeds)
                    │
                    ├─► scan-semgrep.sh ──► extract staged source ──► semgrep
                    │     └─► WARN on security bugs (commit proceeds)
                    │
                    ├─► scan-shellcheck.sh ──► extract staged scripts ──► shellcheck
                    │     └─► WARN on shell script issues (commit proceeds)
                    │
                    ├─► scan-commitlint.sh ──► validate commit message format
                    │     └─► WARN on non-conventional message (commit proceeds)
                    │
                    └─► scan-signing.sh ──► check git gpgsign config
                          └─► WARN if signing not configured (commit proceeds)

                 PostToolUse hook fires
                    │
                    └─► scan-summary.sh ──► aggregate warn findings
                          └─► "SEATBELT SUMMARY: 3 finding(s)..."

  Shared library: hooks/scripts/lib/
    ├── detect-commit.sh   (JSON parsing, commit detection)
    ├── result-dir.sh      (temp directory management)
    └── config.sh          (.seatbelt.yml config loader)
```

## How setup works

`/seatbelt:setup` is a one-stop onboarding command that:

1. Runs the doctor script to detect installed scanners and their versions
2. Shows a health score (`Seatbelt Health: N/6 scanners active`)
3. Groups missing scanners by package manager into batched install commands
4. Asks for your confirmation before running anything
5. Re-runs the doctor after installation to confirm success
6. Runs smoke tests on each newly installed scanner (creates a temp git repo with representative test files, runs the scanner binary directly, and reports OK / FAIL / NEEDS DB)

## Skip / bypass

Bypass all scanners:
```bash
export SKIP_SEATBELT=1
```

Bypass individual scanners:
```bash
export SKIP_GITLEAKS=1
export SKIP_CHECKOV=1
export SKIP_TRIVY=1
export SKIP_ZIZMOR=1
export SKIP_SEMGREP=1
export SKIP_SHELLCHECK=1
export SKIP_COMMITLINT=1
export SKIP_SIGNING=1
```

Suppress specific findings:
- **gitleaks**: Add the fingerprint to `.gitleaksignore`
- **checkov**: Add `#checkov:skip=CKV_XXX:reason` above the affected line

## Commands

### `/seatbelt:setup`

One-stop onboarding: detects missing scanners, proposes install commands grouped by package manager, asks for confirmation, installs, then runs smoke tests to verify each scanner works. Shows a final health score.

### `/seatbelt:doctor`

Checks which scanners are installed, reports versions, shows a health score (`N/6 scanners active`), flags trivy's DB status as a distinct condition, and provides platform-specific install instructions for anything missing. Suggests `/seatbelt:setup` when tools are missing.

### `/seatbelt:scan`

Runs all eight enabled scanners on currently staged files — the same scan that runs at commit time. Use this to check "will my commit pass?" before committing. Reports BLOCKED, WARNINGS, or CLEAN.

## Configuration

Create a `.seatbelt.yml` file in your repo root to disable specific scanners:

```yaml
scanners:
  checkov:
    enabled: false
  semgrep:
    enabled: false
```

Omitted scanners default to enabled. You can also override via environment variables — env vars take precedence over the config file:

```bash
export SEATBELT_CHECKOV_ENABLED=false
```

## Requirements

- **bash** 3.2+ (macOS default is fine)
- **python3** (for JSON parsing in hook scripts; `brew install python3` if not present)
- **git**
- Scanner binaries: any combination of gitleaks, checkov, trivy, zizmor, semgrep, shellcheck

## Supported file types

| Scanner | Files scanned |
|---------|--------------|
| gitleaks | All staged changes |
| checkov | Dockerfile, *.tf, *.tf.json, docker-compose.yml, .github/workflows/*.yml, k8s/*.yml, helm/*.yml |
| trivy | package-lock.json, yarn.lock, pnpm-lock.yaml, Cargo.lock, requirements.txt, poetry.lock, uv.lock, Pipfile.lock, go.sum, Gemfile.lock, composer.lock |
| zizmor | .github/workflows/*.yml, .github/workflows/*.yaml |
| semgrep | *.py, *.js, *.ts, *.jsx, *.tsx, *.java, *.go, *.rb, *.php, *.c, *.cpp, *.cs, *.rs, *.swift, *.kt, *.scala, *.yaml, *.yml |
| shellcheck | *.sh, *.bash |
| commitlint | Commit message (from -m flag) |
| signing | Git config (commit.gpgsign) |

## Scan summary

After scanning, seatbelt shows an aggregate summary of findings from warn-only scanners:

```text
SEATBELT SUMMARY: 3 finding(s) from 2 scanner(s) — trivy: 2 vulnerabilities in package-lock.json; zizmor: 1 issue in ci.yml
```

This summary only appears when there are findings. If all scans are clean, no summary is shown.

## Example output

**Secret detected (commit blocked):**

Gitleaks emits a JSON block decision. The `reason` field contains the truncated gitleaks output showing what was found:

```json
{"decision":"block","reason":"SECRET DETECTED in staged changes — commit blocked.\n\nGitleaks found potential secrets/credentials:\n\nFinding: ...AKIAIOSFODNN7EXAMPLE...\nRuleID: aws-access-key-id\nFile: src/config.js\nLine: 12\n\nFix: Remove the secret from staged files. Use environment variables or a secret manager.\nFalse positive? Add the fingerprint to .gitleaksignore\nBypass once: export SKIP_GITLEAKS=1 in your shell, then retry"}
```

**IaC misconfiguration (commit blocked):**

Checkov also emits a JSON block decision with parsed check IDs in the reason:

```json
{"decision":"block","reason":"IaC MISCONFIGURATION in staged files — commit blocked.\n\ncheckov found failed checks:\n\n  CKV_DOCKER_3 on /Dockerfile (/Dockerfile)\n\nFix: Address the failed checks listed above.\nFalse positive? Add #checkov:skip=CKV_XXX:reason above the affected line\nBypass once: export SKIP_CHECKOV=1 in your shell, then retry"}
```

**Dependency CVEs (warning only, commit proceeds):**

Trivy prints a summary to stderr — no block decision, commit proceeds:

```text
SEATBELT: trivy found 2 vulnerabilities in package-lock.json:
  CVE-2021-23337 [CRITICAL] lodash 4.17.20; CVE-2021-44906 [HIGH] minimist 1.2.5
```

**All clean (no output):**

When all scans pass with no findings, seatbelt produces no output — your commit proceeds silently.

**Scanner not installed (degraded mode):**

```text
SEATBELT DEGRADED: gitleaks not installed — secret scanning DISABLED (brew install gitleaks | /seatbelt doctor)
```

## Troubleshooting

**python3 not found — scans silently skipped**

Seatbelt uses `python3` to parse hook input JSON and detect git commit commands. Without it, the commit-detection library (`detect-commit.sh`) fails open — hooks silently skip scanning rather than blocking. Install it with `brew install python3` (macOS) or `apt-get install python3` (Linux).

**trivy reports "no vulnerability DB cached"**

Trivy needs its vulnerability database downloaded before it can scan. Run:
```bash
trivy image --download-db-only
```

**checkov is slow on first run**

Checkov's first invocation downloads its Python dependencies. Subsequent runs are faster. If it's too slow, bypass it temporarily with `SKIP_CHECKOV=1`.

**Scans don't run on my commits**

Seatbelt only intercepts commits made through Claude Code's Bash tool. Commits made directly in your terminal (outside Claude Code) bypass the plugin hooks. This is by design — seatbelt is a Claude Code plugin, not a git hook.

**False positive from gitleaks**

Add the finding's fingerprint to a `.gitleaksignore` file in your repo root. Run `gitleaks protect --staged` manually to get the fingerprint, then add it to the ignore file.

**I want to suppress a specific checkov rule**

Add a comment above the affected line in your IaC file:
```text
#checkov:skip=CKV_DOCKER_3:We use a non-root user in the entrypoint script
```

## CI Backstop

Seatbelt catches issues at commit time, but commits made outside Claude Code bypass plugin hooks. Add a `security.yml` GitHub Actions workflow as a CI backstop — defense-in-depth that catches what seatbelt misses.

The workflow runs the same scanners (semgrep, checkov, zizmor, trivy) on push and PR, plus SHA pin verification via `.github/scripts/check-pinned-uses.sh`. Trivy auto-skips if a compliance job already exists in `tests.yml`.

See [`ci-pipeline-setup`](https://github.com/chris-yyau/seatbelt/blob/main/.github/workflows/security.yml) for the reference implementation deployed in this repo.

| Scanner | Local (seatbelt) | CI (security.yml) |
|---------|-----------------|-------------------|
| gitleaks | BLOCK | GitGuardian (separate) |
| checkov | BLOCK | BLOCK |
| semgrep | WARN | BLOCK |
| zizmor | WARN | BLOCK + SHA pin check |
| trivy | WARN | BLOCK (auto-skips if compliance job exists) |
| shellcheck | WARN | tests.yml |

## Uninstall

```bash
claude plugin uninstall seatbelt@seatbelt
claude plugin marketplace remove seatbelt
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and how to add new scanners.

## Security

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## License

MIT
