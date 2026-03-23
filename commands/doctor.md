---
name: doctor
description: Check which security scanners are installed and get install guidance
---

# Seatbelt Doctor

Run the diagnostic script and present results to the user.

## Steps

1. Run the doctor script:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh
```

2. Parse the JSON output and present a status table:

| Scanner | Status | Version | Fail Mode |
|---------|--------|---------|-----------|
| gitleaks | installed/missing | version | BLOCK |
| checkov | installed/missing | version | BLOCK |
| trivy | installed/missing | version | warn |
| zizmor | installed/missing | version | warn |

3. For each missing tool, provide install commands based on the detected `platform` and `package_managers` array from the JSON output. Only suggest installers that are available on the user's machine:

**gitleaks:**
- If `brew` in package_managers: `brew install gitleaks`
- Otherwise: download binary from https://github.com/gitleaks/gitleaks/releases

**checkov:**
- If `pip3` in package_managers: `pip3 install checkov`
- If `brew` in package_managers: `brew install checkov`

**trivy:**
- If `brew` in package_managers: `brew install trivy`
- Otherwise: download binary from https://github.com/aquasecurity/trivy/releases (note: `apt-get install trivy` requires adding Aqua's APT repository first)

**zizmor:**
- If `pip3` in package_managers: `pip3 install zizmor`
- If `cargo` in package_managers: `cargo install zizmor`

4. Briefly explain what each scanner does:
- **gitleaks**: Scans for hardcoded secrets, API keys, and credentials in staged changes
- **checkov**: Checks Infrastructure-as-Code files (Dockerfiles, Terraform, k8s) for security misconfigurations
- **trivy**: Scans dependency lock files for known HIGH/CRITICAL vulnerabilities (CVEs)
- **zizmor**: Checks GitHub Actions workflows for security issues (injection risks, unpinned actions)
