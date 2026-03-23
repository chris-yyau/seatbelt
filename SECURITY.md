# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Seatbelt, please report it responsibly.

**Email:** Create an issue on GitHub with the label `security`, or contact the maintainer directly.

**Response timeline:**
- Acknowledgment within 48 hours
- Assessment within 1 week
- Fix or mitigation within 2 weeks for critical issues

## Scope

- All hook scripts (`hooks/scripts/scan-*.sh`)
- Doctor diagnostic script (`scripts/doctor.sh`)
- Plugin manifest and hooks configuration
- Command definitions

## Out of Scope

- Vulnerabilities in the scanner binaries themselves (gitleaks, checkov, trivy, zizmor) — report those to their respective projects
- Claude Code platform vulnerabilities — report those to Anthropic

## Recognition

We appreciate responsible disclosure and will credit reporters in the fix commit.
