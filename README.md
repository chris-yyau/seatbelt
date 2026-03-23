# Seatbelt

Zero-config security scanning for vibe coders. Seatbelt is a [Claude Code plugin](https://docs.anthropic.com/en/docs/claude-code/plugins) that runs security scanners automatically before every `git commit`.

## What it does

Seatbelt intercepts `git commit` commands and runs four security scanners on your staged changes:

| Scanner | What it checks | Fail mode |
|---------|---------------|-----------|
| **gitleaks** | Hardcoded secrets, API keys, credentials | BLOCK — commit is prevented |
| **checkov** | IaC misconfigurations (Dockerfile, Terraform, k8s, Helm, GitHub Actions, docker-compose) | BLOCK — commit is prevented |
| **trivy** | Dependency CVEs in lock files (HIGH/CRITICAL severity) | warn — findings shown, commit allowed |
| **zizmor** | GitHub Actions workflow security issues (injection, unpinned actions) | warn — findings shown, commit allowed |

Scanners that aren't installed are silently skipped with a degraded-mode warning. Install what you need — Seatbelt works with any combination.

## Install

```bash
claude plugin add seatbelt
```

Then install the scanner binaries you want:

```bash
# macOS (recommended: install all four)
brew install gitleaks checkov trivy
pip3 install zizmor

# Linux
brew install gitleaks trivy
pip3 install checkov zizmor

# Check what's installed
/seatbelt doctor
```

## How it works

Each scanner runs as a [PreToolUse hook](https://docs.anthropic.com/en/docs/claude-code/hooks) that fires before every Bash tool invocation. The hooks:

1. Read the tool invocation JSON from stdin
2. Check if the command contains `git commit`
3. If yes, run the relevant scanner on staged files
4. Emit `{"decision":"block"}` (gitleaks/checkov) or print warnings (trivy/zizmor)

Non-commit commands (npm install, git push, grep, etc.) pass through instantly — the fast pre-filter adds negligible overhead.

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

### `/seatbelt doctor`

Checks which scanners are installed, reports versions, and provides platform-specific install instructions for anything missing.

## Requirements

- **bash** 3.2+ (macOS default is fine)
- **python3** (for JSON parsing in hook scripts)
- **git** (obviously)
- Scanner binaries: install any combination of gitleaks, checkov, trivy, zizmor

## Supported file types

| Scanner | Files scanned |
|---------|--------------|
| gitleaks | All staged changes |
| checkov | Dockerfile, *.tf, docker-compose.yml, .github/workflows/*.yml, k8s/*.yml, helm/*.yml |
| trivy | package-lock.json, yarn.lock, pnpm-lock.yaml, Cargo.lock, requirements.txt, poetry.lock, uv.lock, Pipfile.lock, go.sum, Gemfile.lock, composer.lock |
| zizmor | .github/workflows/*.yml, .github/workflows/*.yaml |

## License

MIT
