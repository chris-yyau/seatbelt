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

Add the marketplace and install the plugin:

```bash
claude plugin marketplace add chris-yyau/seatbelt
claude plugin install seatbelt@seatbelt
```

Then install the scanner binaries you want:

```bash
# macOS (recommended: install all four)
brew install gitleaks trivy
pip3 install checkov zizmor

# Linux
pip3 install checkov zizmor
# gitleaks: https://github.com/gitleaks/gitleaks/releases
# trivy: https://github.com/aquasecurity/trivy/releases

# Check what's installed
/seatbelt:doctor
```

## How it works

Seatbelt registers [PreToolUse hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) on the Bash tool. Each hook receives the command as JSON, checks if it contains `git commit` via a fast string pre-filter, and exits immediately if not — so non-commit commands have near-zero overhead.

When a `git commit` is detected:

- **gitleaks** runs `gitleaks protect --staged` on the staged diff
- **checkov** scans staged IaC files by name (Dockerfiles, Terraform, k8s manifests, etc.) using the working tree copy
- **trivy** scans lock files (package-lock.json, Cargo.lock, go.sum, etc.) present in the staged file list for known CVEs, using the on-disk copy
- **zizmor** scans GitHub Actions workflow files present in the staged file list

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

### `/seatbelt:doctor`

Checks which scanners are installed, reports versions, and provides platform-specific install instructions for anything missing.

## Requirements

- **bash** 3.2+
- **python3** (for JSON parsing in hook scripts)
- **git**
- Scanner binaries: any combination of gitleaks, checkov, trivy, zizmor

## Supported file types

| Scanner | Files scanned |
|---------|--------------|
| gitleaks | All staged changes |
| checkov | Dockerfile, *.tf, docker-compose.yml, .github/workflows/*.yml, k8s/*.yml, helm/*.yml |
| trivy | package-lock.json, yarn.lock, pnpm-lock.yaml, Cargo.lock, requirements.txt, poetry.lock, uv.lock, Pipfile.lock, go.sum, Gemfile.lock, composer.lock |
| zizmor | .github/workflows/*.yml, .github/workflows/*.yaml |

## Uninstall

```bash
claude plugin uninstall seatbelt@seatbelt
claude plugin marketplace remove seatbelt
```

## License

MIT
