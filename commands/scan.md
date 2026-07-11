---
name: scan
description: Run all enabled seatbelt scanners on staged files (parity with commit-time behavior)
---

# Seatbelt Scan

Run all eight enabled security scanners on currently staged files. This is the same scan that runs at commit time, so you can check "will my commit pass?" before committing.

## Prerequisites

Check if there are staged changes:
```bash
git diff --cached --quiet 2>/dev/null
```
If exit code is 0 (no staged changes), tell the user: "No files are staged. Stage files with `git add` first, then retry."

## Execution

Run each scanner script, piping a synthetic git commit hook input. Each scanner clears only its own result file, so the scanner order does not affect correctness — but run `scan-summary.sh` **last**, since it aggregates the per-scanner results and then removes the shared result directory. Keeping the order aligned with `hooks.json` also keeps this command's output consistent with commit-time behavior.

Define the synthetic input once (it simulates a git commit command), then reuse it for every scanner:
```bash
INPUT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"chore: seatbelt scan\""}}'
echo "$INPUT" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-gitleaks.sh"
echo "$INPUT" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-checkov.sh"
echo "$INPUT" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-trivy.sh"
echo "$INPUT" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-zizmor.sh"
echo "$INPUT" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-semgrep.sh"
echo "$INPUT" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-shellcheck.sh"
echo "$INPUT" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-commitlint.sh"
echo "$INPUT" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-signing.sh"
```

Then run the summary aggregator last:
```bash
echo "$INPUT" | bash "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-summary.sh"
```

## Presenting Results

After all scanners complete:

1. If any scanner emitted a JSON block decision on stdout (`{"decision":"block",...}`): report as **BLOCKED** with the reason
2. If scanners emitted warnings on stderr but no blocks: report as **WARNINGS** with findings listed
3. If no findings at all: report as **CLEAN** -- "All scanners passed. Your commit will not be blocked by seatbelt."

Note: Disabled scanners (via `.seatbelt.yml` or `SEATBELT_<SCANNER>_ENABLED=false`) will silently skip. Uninstalled scanners will show "DEGRADED" warnings on stderr.
