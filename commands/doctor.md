---
name: doctor
description: Check scanner health, show health score, and suggest /seatbelt:setup for missing tools
---

# Seatbelt Doctor

Run the diagnostic script and present a full health report.

## Steps

1. Run the doctor script:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh
```

2. Parse the JSON output. Compute the health score:
   - Count a scanner as **active** only if it is installed AND (for trivy) `db_cached` is true
   - trivy installed with `db_cached=false` counts as **degraded**, not active
   - Show the score prominently: **Seatbelt Health: N/4 scanners active**

3. Present a status table with fail mode:

| Scanner | Status | Version | Fail Mode |
|---------|--------|---------|-----------|
| gitleaks | installed/missing | version or — | BLOCK |
| checkov | installed/missing | version or — | BLOCK |
| trivy | installed/missing/degraded (no DB) | version or — | warn |
| zizmor | installed/missing | version or — | warn |

For trivy: if it is installed but `db_cached` is false in the JSON output, show status as **"degraded (no DB)"** rather than installed. This is a distinct condition — trivy cannot scan dependencies without its vulnerability database. The binary is present but the scanner is non-functional.

4. If any scanners are missing (not installed), suggest:
   > Run `/seatbelt:setup` to install missing scanners and verify they work.

   If trivy is installed but has no DB, suggest directly (do NOT suggest `/seatbelt:setup` for this — setup exits when all binaries are present):
   > Run `trivy image --download-db-only` to download the vulnerability database and activate trivy dependency scanning.

5. For each missing tool, provide install commands based on the detected `platform` and `package_managers` array from the JSON output. Only suggest installers that are available on the user's machine:

**gitleaks** — Scans for hardcoded secrets, API keys, and credentials in staged changes:
- If `brew` in package_managers: `brew install gitleaks`
- If `go` in package_managers: `go install github.com/gitleaks/gitleaks/v8@latest`
- Otherwise: download binary from https://github.com/gitleaks/gitleaks/releases

**checkov** — Checks Infrastructure-as-Code files (Dockerfiles, Terraform, k8s) for security misconfigurations:
- If `pip3` in package_managers: `pip3 install checkov`
- If `brew` in package_managers: `brew install checkov`

**trivy** — Scans dependency lock files for known HIGH/CRITICAL vulnerabilities (CVEs):
- If `brew` in package_managers: `brew install trivy`
- Otherwise: follow install guide at https://aquasecurity.github.io/trivy/latest/getting-started/installation/ (note: `apt-get install trivy` requires adding Aqua's APT repository first)

**zizmor** — Checks GitHub Actions workflows for security issues (injection risks, unpinned actions):
- If `pip3` in package_managers: `pip3 install zizmor`
- If `cargo` in package_managers: `cargo install zizmor`

6. If all 4 scanners are installed and trivy has a DB:
   - Show "All 4 scanners active — seatbelt is fully operational."
   - No further action needed.
