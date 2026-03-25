---
name: setup
description: Install and verify security scanners for seatbelt
---

# Seatbelt Setup

Detect missing scanners, install them with user confirmation, and verify they work.

## Steps

1. Run the doctor script to detect current state:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh
```

2. Parse the JSON output. Show a status table:

| Scanner | Status | Version | Fail Mode |
|---------|--------|---------|-----------|
| gitleaks | installed/missing | version or — | BLOCK |
| checkov | installed/missing | version or — | BLOCK |
| trivy | installed/missing | version or — | warn |
| zizmor | installed/missing | version or — | warn |
| semgrep | installed/missing | version or — | warn |
| shellcheck | installed/missing | version or — | warn |

Show the health score: `Seatbelt Health: N/6 scanners active`

3. If all 6 scanners are installed:
   - Show "All 6 scanners active — seatbelt is fully operational."
   - If trivy is installed but `db_cached` is false, note: "trivy is installed but has no vulnerability database. Run `trivy image --download-db-only` to enable dependency scanning."
   - Exit.

4. If scanners are missing, collect the `install_cmd` for each missing tool from the doctor output. Group commands by package manager into batches. For example:
   - If gitleaks and trivy are both missing and both use brew: `brew install gitleaks trivy`
   - If checkov and semgrep both use pip3: `pip3 install checkov semgrep`

5. Present the install plan to the user. Show each command that will be run. Ask for confirmation before executing. Example:

   > **Missing scanners: checkov, zizmor**
   >
   > I'll run these commands to install them:
   > ```
   > pip3 install checkov zizmor
   > ```
   > Proceed?

6. After user confirms, execute each batch command. Show output.

7. Re-run doctor.sh to verify installation succeeded. Show updated status table.

8. For each newly installed scanner, run a quick smoke test:
   - Create a temp directory with `mktemp -d`
   - Initialize a git repo with `git init`
   - Create appropriate test files per scanner:
     - gitleaks: a file containing `AKIAIOSFODNN7EXAMPLE` (fake AWS key pattern)
     - checkov: a minimal `Dockerfile` with `FROM ubuntu:latest`
     - trivy: a minimal `package-lock.json` with `{"name":"test","lockfileVersion":2}`
     - zizmor: a minimal `.github/workflows/test.yml` with `on: push`
     - semgrep: a temp Python file with `import subprocess; subprocess.call(cmd, shell=True)` (triggers command injection detection)
   - For trivy: if `db_cached` is false, run `trivy image --download-db-only` first. If download fails, report as "NEEDS DB" instead of running the scan.
   - Stage the files with `git add`
   - Run each scanner binary directly (not via hooks):
     - `gitleaks protect --staged --no-banner`
     - `checkov --file <path> --framework dockerfile --quiet`
     - `trivy fs --scanners vuln --severity HIGH,CRITICAL --skip-db-update --no-progress <path>`
     - `zizmor --no-progress <path>`
     - semgrep: Two phases:
       1. Rule download: `semgrep --config p/security-audit --validate`. If this fails, report as "NEEDS RULES" (analogous to trivy's "NEEDS DB")
       2. Scan test: `semgrep scan --config p/security-audit --json --quiet <path>`. Expect at least one finding.
     - shellcheck: `shellcheck --version` to verify it works
   - Report result per scanner: OK (ran successfully), FAIL (errored), or NEEDS DB (trivy without DB)
   - Clean up the temp directory

9. Show final summary:
   > **Seatbelt Health: 6/6 scanners active**
   >
   > | Scanner | Status | Smoke Test |
   > |---------|--------|------------|
   > | gitleaks | installed | OK |
   > | checkov | installed | OK |
   > | trivy | installed | OK |
   > | zizmor | installed | OK |
   > | semgrep | installed | OK |
   > | shellcheck | installed | OK |
   >
   > Setup complete. Seatbelt will scan your staged changes before every commit.

10. If any install failed or smoke test failed, do NOT say setup is complete. Instead show what failed and suggest running the scanner manually to diagnose.
