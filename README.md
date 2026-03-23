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
brew install gitleaks checkov trivy zizmor

# Linux (brew if available, otherwise pip3/releases)
brew install gitleaks checkov trivy zizmor
# Or without brew:
#   gitleaks: https://github.com/gitleaks/gitleaks/releases
#   trivy:    https://github.com/aquasecurity/trivy/releases
#   checkov:  pip3 install checkov
#   zizmor:   pip3 install zizmor (or cargo install zizmor)

# Check what's installed
/seatbelt:doctor
```

## How it works

Seatbelt registers [PreToolUse hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) on the Bash tool. Each hook checks if the command is a `git commit` and exits immediately if not — non-commit commands have near-zero overhead.

When a `git commit` is detected:

- **gitleaks** scans the staged diff for secrets
- **checkov** scans IaC files that appear in the staged file list (Dockerfiles, Terraform, k8s manifests, etc.)
- **trivy** scans lock files that appear in the staged file list for known CVEs
- **zizmor** scans workflow files that appear in the staged file list

Note: gitleaks scans the actual staged diff. The other three scan the on-disk copy of files identified in the staging area.

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

## Uninstall

```bash
claude plugin uninstall seatbelt@seatbelt
claude plugin marketplace remove seatbelt
```

## License

MIT
