# Seatbelt

Zero-config security scanning for vibe coders. Seatbelt is a [Claude Code plugin](https://docs.anthropic.com/en/docs/claude-code/plugins) that automatically scans your staged changes before every `git commit`.

## What it does

Seatbelt intercepts `git commit` commands and runs four security scanners on your staged changes:

| Scanner | What it checks | Fail mode |
|---------|---------------|-----------|
| **gitleaks** | Hardcoded secrets, API keys, credentials | BLOCK — commit is prevented |
| **checkov** | IaC misconfigurations (Dockerfile, Terraform, k8s, Helm, GitHub Actions, docker-compose) | BLOCK — commit is prevented |
| **trivy** | Dependency CVEs in lock files (HIGH/CRITICAL severity) | warn — findings shown, commit allowed |
| **zizmor** | GitHub Actions workflow security issues (injection, unpinned actions) | warn — findings shown, commit allowed |

You don't need all four installed. Scanners that aren't found are skipped with a warning like:

```
SEATBELT DEGRADED: gitleaks not installed — secret scanning DISABLED (brew install gitleaks | /seatbelt:doctor)
```

Install any combination you want — Seatbelt works with one scanner or all four.

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
# macOS (recommended: install all four)
brew install gitleaks checkov trivy zizmor

# Linux (brew if available, otherwise pip3/releases)
brew install gitleaks checkov trivy zizmor
# Or without brew:
#   gitleaks: https://github.com/gitleaks/gitleaks/releases
#   trivy:    https://aquasecurity.github.io/trivy/latest/getting-started/installation/
#   checkov:  pip3 install checkov
#   zizmor:   pip3 install zizmor (or cargo install zizmor)
```

## How it works

Seatbelt registers [PreToolUse hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) on the Bash tool. Each hook checks if the command is a `git commit` and exits immediately if not — non-commit commands have near-zero overhead.

When a `git commit` is detected, seatbelt uses two approaches to scan staged content:

- **gitleaks** reads the git staging area directly via its `--staged` flag
- **checkov, trivy, zizmor** extract staged file content to a temp directory via `git show`, then scan the extracted files. This ensures scanners see exactly what will be committed, not the current working tree.

All four scanner hooks share a common commit-detection library (`hooks/scripts/lib/detect-commit.sh`) that parses Claude Code's hook input JSON to determine if the command is a `git commit`. Non-commit commands are ignored with near-zero overhead.

If you use partial staging (`git add -p`), seatbelt scans exactly the hunks you staged.

## How setup works

`/seatbelt:setup` is a one-stop onboarding command that:

1. Runs the doctor script to detect installed scanners and their versions
2. Shows a health score (`Seatbelt Health: N/4 scanners active`)
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
```

Suppress specific findings:
- **gitleaks**: Add the fingerprint to `.gitleaksignore`
- **checkov**: Add `#checkov:skip=CKV_XXX:reason` above the affected line

## Commands

### `/seatbelt:setup`

One-stop onboarding: detects missing scanners, proposes install commands grouped by package manager, asks for confirmation, installs, then runs smoke tests to verify each scanner works. Shows a final health score.

### `/seatbelt:doctor`

Checks which scanners are installed, reports versions, shows a health score (`N/4 scanners active`), flags trivy's DB status as a distinct condition, and provides platform-specific install instructions for anything missing. Suggests `/seatbelt:setup` when tools are missing.

## Requirements

- **bash** 3.2+ (macOS default is fine)
- **python3** (for JSON parsing in hook scripts; `brew install python3` if not present)
- **git**
- Scanner binaries: any combination of gitleaks, checkov, trivy, zizmor

## Supported file types

| Scanner | Files scanned |
|---------|--------------|
| gitleaks | All staged changes |
| checkov | Dockerfile, *.tf, *.tf.json, docker-compose.yml, .github/workflows/*.yml, k8s/*.yml, helm/*.yml |
| trivy | package-lock.json, yarn.lock, pnpm-lock.yaml, Cargo.lock, requirements.txt, poetry.lock, uv.lock, Pipfile.lock, go.sum, Gemfile.lock, composer.lock |
| zizmor | .github/workflows/*.yml, .github/workflows/*.yaml |

## Scan summary

After scanning, seatbelt shows an aggregate summary of findings from warn-only scanners:

```text
SEATBELT SUMMARY: 3 finding(s) from 2 scanner(s) — trivy: 2 vulnerabilities in package-lock.json; zizmor: 1 issue in ci.yml
```

This summary only appears when there are findings. If all scans are clean, no summary is shown.

## Uninstall

```bash
claude plugin uninstall seatbelt@seatbelt
claude plugin marketplace remove seatbelt
```

## License

MIT
