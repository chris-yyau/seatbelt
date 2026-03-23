<!-- design-reviewed: PASS -->

# Seatbelt v1 — Design Spec

**Date:** 2026-03-23
**Status:** Approved
**Author:** Human + Claude (council-validated)

## Overview

Seatbelt is an open-source Claude Code plugin that bundles 4 deterministic security scanners as zero-config pre-commit hooks for vibe coders. It wires gitleaks, checkov, trivy, and zizmor into Claude Code's PreToolUse hook system so they run automatically before `git commit`.

**Positioning:** "Code hygiene automation" — not "security assurance." Avoids the false confidence trap where users think "pipeline passed = code is secure."

**Target audience:** Developers who use AI to write code they don't fully understand and need guardrails they don't have to configure. Secondary audience: team leads managing AI-assisted juniors.

**Distribution:** Claude Code plugin marketplace. MIT license.

## Plugin Structure

```
seatbelt/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── hooks/
│   ├── hooks.json               # 4 PreToolUse entries, one per scanner
│   └── scripts/
│       ├── scan-gitleaks.sh     # Secret detection       (BLOCK)
│       ├── scan-checkov.sh      # IaC misconfigs         (BLOCK)
│       ├── scan-trivy.sh        # Dependency CVEs        (warn)
│       └── scan-zizmor.sh       # GH Actions security    (warn)
├── commands/
│   └── doctor.md                # /seatbelt doctor command
├── scripts/
│   └── doctor.sh                # Deterministic tool detection (JSON output)
├── LICENSE                      # MIT
└── README.md
```

**Two component types:** Hooks (mechanical, bash) and one command (doctor). No skills. No SessionStart hooks.

## Design Decisions

Each major decision was validated by a 4-voice AI council (Claude Architect + Fresh Claude Skeptic + Gemini Pragmatist + Codex Critic).

| Decision | Chosen | Rationale |
|----------|--------|-----------|
| Hook architecture | 4 independent scripts, no shared library | Isolation > DRY for bash plugins. A crash in one scanner never affects others. 160 lines of zero-coupling code is simpler than shared lib + path resolution glue. (Council #1: Skeptic + Gemini shifted from shared lib to independent scripts) |
| Missing tool behavior | Loud degraded warning + `/seatbelt doctor` | False confidence from quiet skipping is worse than no plugin. Users who see "DEGRADED" can run `/seatbelt doctor` for install guidance. (Council #2: Skeptic challenged premise, Codex identified false confidence as core risk) |
| v1 scope | Hooks + doctor only | Remediation skill cut — hook block messages are the remediation surface. SessionStart hook cut — wrong moment for warnings. `/seatbelt status` deferred to v2. (Council #3 + #5) |
| Doctor implementation | Bash script (facts) + markdown command (presentation) | "Markdown should orchestrate and explain. Bash should decide facts." Deterministic detection is reusable in CI/bug reports. (Council #4: Codex shifted from pure markdown to hybrid) |
| Remediation approach | Rich block messages, no auto-activating skill | Don't add a compensating layer for output you control. Fix the hook messages at the source. Avoids "suppression copilot" behavior. (Council #5: Skeptic + Codex shifted from skill to rich messages) |
| Fail-open on tool errors | All scanners fail-open on tool errors | Tool bugs shouldn't punish users. Fail-closed only on actual findings. Conscious tradeoff — revisit if tool error rate is high. |
| python3 for JSON parsing | Keep python3, graceful fallback | python3 is more commonly available than jq. Fast case-match pre-filter catches most non-commit calls without python3. If python3 missing, hook skips (fail-open). |

## hooks.json

Located at `hooks/hooks.json` — Claude Code auto-discovers this file in the `hooks/` directory of the plugin root (standard plugin convention, no `plugin.json` pointer needed).

Four independent PreToolUse entries. Each matches `Bash` and runs its own scanner script. Claude Code provides each entry its own copy of stdin.

```json
{
  "hooks": [
    {
      "type": "PreToolUse",
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-gitleaks.sh"
        }
      ]
    },
    {
      "type": "PreToolUse",
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-checkov.sh"
        }
      ]
    },
    {
      "type": "PreToolUse",
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-trivy.sh"
        }
      ]
    },
    {
      "type": "PreToolUse",
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-zizmor.sh"
        }
      ]
    }
  ]
}
```

## Claude Code Hook Contract

PreToolUse hooks receive JSON on **stdin** describing the tool call about to execute. The hook communicates back via **stdout** and **stderr**:

**Stdin schema (relevant fields):**
```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m \"feat: add feature\""
  }
}
```

Note: field names may appear as `tool_name` or `toolName`, and `tool_input` or `toolInput`. Scripts must handle both.

**Response protocol:**
- **stdout `{"decision":"block","reason":"..."}` JSON** — Claude Code blocks the tool call and shows the reason to the user. This is the BLOCK mechanism.
- **stderr** — displayed to the user as informational context. This is the WARN mechanism.
- **exit code 0** — hook completed normally (whether it blocked or not). The `{"decision":"block"}` JSON in stdout is what determines blocking, not the exit code.
- **Any exit code** — Claude Code does not use exit codes for block/allow decisions. Exit 0 is conventional for clean completion.

**Execution model:** Claude Code runs all PreToolUse hook entries for a given matcher. Each entry receives its own copy of stdin. Execution order is not guaranteed. Scripts should not depend on ordering or shared state between hooks.

## Hook Scripts

### Shared Pattern

Each of the 4 scanner scripts is self-contained (~100-120 lines) and follows the same pattern. Shebang: `#!/usr/bin/env bash` (uses PATH-resolved bash, works on macOS with brew bash and on Linux).

```
1. set -euo pipefail + ERR trap (behavior depends on scanner's fail mode)
2. Check SKIP_SEATBELT=1 or per-scanner SKIP_* env var → exit 0 if set
3. Consume stdin (HOOK_DATA=$(cat 2>/dev/null || true))
4. Fast case-match pre-filter: only fire on "git commit" patterns
5. python3 JSON parsing: verify tool_name=Bash and command contains git commit
6. Check if scanner binary exists → if missing, emit loud degraded warning, exit 0
7. Collect staged files (where relevant, using --diff-filter=ACM to exclude deletes)
8. Run scanner on staged files
9. Emit results: {"decision":"block"} on stdout for BLOCK scanners, stderr for warn scanners
```

### Step 4: Fast Case-Match Pre-Filter

Before spending time on python3 JSON parsing, a bash `case` statement does a fast string match on the raw stdin data. This eliminates the vast majority of non-commit Bash tool calls (file reads, npm commands, etc.) with zero overhead.

```bash
case "$HOOK_DATA" in
    *\"Bash\"*git\ commit*) ;;
    *git\ commit*\"Bash\"*) ;;
    *) exit 0 ;;
esac
```

This matches any stdin containing both `"Bash"` and `git commit`. False positives (e.g., a grep for "git commit") are filtered by the python3 parsing in step 5. The pre-filter is intentionally loose — it's a performance gate, not a correctness gate.

### Step 5: python3 JSON Parsing

After the pre-filter, python3 does precise parsing. **Critical data flow:** HOOK_DATA is piped into python3 via `printf` — stdin was already consumed in Step 3, so the python script reads from the pipe, not from stdin directly. Output is captured into a bash variable via command substitution (never reaches hook stdout).

```bash
IS_GIT_COMMIT=$(printf '%s' "$HOOK_DATA" | python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
    tool = d.get('tool_name', d.get('toolName', ''))
    if tool != 'Bash':
        sys.exit(0)
    inp = d.get('tool_input', d.get('toolInput', {}))
    if isinstance(inp, str):
        inp = json.loads(inp)
    cmd = inp.get('command', '')
    for seg in re.split(r'&&|\|\||[;\n|]', cmd):
        seg = seg.strip()
        while re.match(r'^\w+=\S*\s', seg):
            seg = re.sub(r'^\w+=\S*\s+', '', seg, count=1)
        if re.match(r'git\s+commit\b', seg):
            print('yes')
            break
except Exception:
    pass
" 2>/dev/null || true)

[ "$IS_GIT_COMMIT" != "yes" ] && exit 0
```

This handles: `git commit`, `git commit -m "..."`, `git commit --amend`, `VAR=1 git commit`, and chained commands (`cmd1 && git commit`). Each script includes this inline (no shared file).

**Known limitations:** Does not detect `/usr/bin/git commit` or `git -C repo commit`. These are rare in Claude Code tool calls (Claude uses plain `git commit`) and are accepted as v1 limitations.

### Block Message Emission

All BLOCK scripts must safely construct JSON for stdout. Raw bash string interpolation breaks on multi-line, quote-containing block messages. Each script includes this inline `block_emit()` function:

```bash
block_emit() {
    local reason="$1"
    if command -v jq &>/dev/null; then
        jq -n --arg r "$reason" '{"decision":"block","reason":$r}'
    else
        local escaped
        escaped=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | head -c 2000)
        printf '{"decision":"block","reason":"%s"}\n' "$escaped"
    fi
}
```

Usage: `block_emit "$REASON"` — outputs valid JSON to stdout.

### Fail Modes

| Scanner | What it scans | On finding | On missing tool | On tool error | Skip env var |
|---------|--------------|-----------|-----------------|---------------|-------------|
| gitleaks | Secrets, API keys, tokens in staged changes | **BLOCK** (secrets in git history are catastrophic) | Loud degraded warning, skip | Pass through (fail-open) | `SKIP_GITLEAKS=1` |
| checkov | IaC misconfigs (Dockerfile, Terraform, k8s, GH Actions, docker-compose, Helm) | **BLOCK** (IaC vuln on prod = high cost) | Loud degraded warning, skip | Pass through (fail-open) | `SKIP_CHECKOV=1` |
| trivy | HIGH/CRITICAL CVEs in dependency lock files | Warn only (stderr) | Loud degraded warning, skip | Pass through (fail-open) | `SKIP_TRIVY=1` |
| zizmor | GH Actions workflow security issues | Warn only (stderr) | Loud degraded warning, skip | Pass through (fail-open) | `SKIP_ZIZMOR=1` |

Global skip: `SKIP_SEATBELT=1` (skips all scanners).

### Degraded-Mode Warning

When a scanner binary is not installed, the hook emits a concise, 1-line warning on every commit attempt:

```
⚠️ SEATBELT DEGRADED: gitleaks not installed — secret scanning DISABLED (brew install gitleaks | /seatbelt doctor)
```

Design decision: warnings fire on every commit, not once. This ensures the user cannot miss it. If warning fatigue leads them to `SKIP_SEATBELT=1`, that is a conscious choice. The warning is kept to 1 line to minimize noise.

### Output Truncation Policy

All scanner output included in block messages or warnings is truncated to prevent overwhelming the user and the context window:

| Scanner | Truncation |
|---------|-----------|
| gitleaks | First 20 lines of scanner output |
| checkov | First 3 FAILED lines |
| trivy | First 5 HIGH/CRITICAL lines |
| zizmor | First 3 finding lines |

The full, untruncated output is always available by running the scanner manually.

### Rich Block Messages

When a BLOCK scanner finds an issue, the block message is self-contained remediation. Each message includes:

1. **What was found** — rule ID + human-readable explanation
2. **Why it matters** — 1-line risk statement
3. **How to fix it** — specific actionable step
4. **How to suppress** — tool's native mechanism (if false positive)
5. **One-time bypass** — `SKIP_*=1` env var

Example (gitleaks):

```
SECRET DETECTED in staged changes — commit blocked.

Gitleaks found potential secrets/credentials:

[scanner output, truncated to first 20 lines]

Fix: Remove the secret from staged files. Use environment variables or a secret manager.
False positive? Add the fingerprint to .gitleaksignore
Bypass once: export SKIP_GITLEAKS=1 in your shell, then retry
```

Example (checkov):

```
IaC MISCONFIGURATION in staged files — commit blocked.

checkov found failed checks:

CKV_DOCKER_2: Ensure that HEALTHCHECK instructions have been added to container images
  File: Dockerfile, Line: 1

Fix: Add HEALTHCHECK instruction to your Dockerfile.
False positive? Add #checkov:skip=CKV_DOCKER_2:reason above the line
Bypass once: export SKIP_CHECKOV=1 in your shell, then retry
```

### Scanner-Specific Details

**scan-gitleaks.sh:**
- Runs `gitleaks protect --staged --no-banner` on staged changes
- Exit code 0 = no leaks, exit code 1 = leaks found (BLOCK)
- Other exit codes = tool error (pass through)

**scan-checkov.sh:**
- Collects staged files (`git diff --cached --name-only --diff-filter=ACM`), filters for IaC file patterns
- Framework mapping from file pattern to checkov `--framework` value:

| File pattern | Checkov framework |
|---|---|
| `*Dockerfile*`, `*dockerfile*` | `dockerfile` |
| `*.tf`, `*.tf.json` | `terraform` |
| `*docker-compose*.yml`, `*docker-compose*.yaml` | `docker_compose` |
| `.github/workflows/*.yml`, `.github/workflows/*.yaml` | `github_actions` |
| `*k8s*/*.yml`, `*k8s*/*.yaml`, `*kubernetes*/*.yml`, `*kubernetes*/*.yaml` | `kubernetes` |
| `*helm*/*.yml`, `*helm*/*.yaml` | `helm` |

- Files not matching any pattern are skipped (not passed to checkov)
- Runs `checkov --file <file> --framework <framework> --compact --quiet` per matched file
- Supports both `checkov` binary and `python3 -m checkov.main` fallback
- Any FAILED check = BLOCK
- Parse errors = warn (stderr), not block. Rationale: parse errors are tool-level failures, not security findings. Consistent with the fail-open-on-tool-errors design decision.

**scan-trivy.sh:**
- Collects staged lock files (`git diff --cached --name-only --diff-filter=ACM`), filters for: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `requirements.txt`, `poetry.lock`, `uv.lock`, `Pipfile.lock`, `go.sum`, `Gemfile.lock`, `composer.lock`
- DB existence check: looks for trivy DB cache directory. Resolution order:
  1. `$TRIVY_CACHE_DIR/db/` if `TRIVY_CACHE_DIR` is set
  2. `~/Library/Caches/trivy/db/` on macOS
  3. `~/.cache/trivy/db/` on Linux
  4. If directory is missing or empty, skip trivy entirely with informational message: "trivy: no vulnerability DB cached — run 'trivy image --download-db-only' to enable dep scanning"
- Runs `trivy fs --scanners vuln --severity HIGH,CRITICAL --skip-db-update --no-progress <file>` per lock file
- 30-second timeout per file. Timeout command resolution: prefer `timeout` (Linux), fall back to `gtimeout` (macOS via `brew install coreutils`). If neither available, run without timeout (accepts hang risk over skipping trivy entirely).
- Finding detection: grep for `Total: [1-9]` in output (non-zero vulnerability count)
- Findings = stderr warning only, truncated to first 5 HIGH/CRITICAL lines

**scan-zizmor.sh:**
- Collects staged GitHub Actions workflow files (`git diff --cached --name-only --diff-filter=ACM`), filters for `.github/workflows/*.yml` and `.github/workflows/*.yaml`
- Runs `zizmor --no-progress <file>` per workflow file
- Finding detection: grep for `(warning|error)\[` pattern in output (zizmor uses `warning[rule-name]` and `error[rule-name]` format)
- Count findings: `grep -cE '(warning|error)\['`
- Findings = stderr warning only, showing scanner name, finding count, and first 3 finding lines

## `/seatbelt doctor` Command

Two layers: bash script for deterministic facts, markdown command for conversational presentation.

### scripts/doctor.sh

Outputs machine-readable JSON to stdout:

```json
{
  "gitleaks": {"installed": true, "version": "8.18.0", "path": "/opt/homebrew/bin/gitleaks"},
  "checkov": {"installed": false, "version": null, "path": null},
  "trivy": {"installed": true, "version": "0.52.0", "path": "/opt/homebrew/bin/trivy"},
  "zizmor": {"installed": false, "version": null, "path": null},
  "platform": "darwin-arm64",
  "package_managers": ["brew", "pip3", "cargo"]
}
```

Detection logic:
- Tool presence: `command -v <tool>` (for checkov: also checks `python3 -c "import checkov"` as fallback, matching the hook's `python3 -m checkov.main` fallback)
- Version: tool-specific version command (e.g., `gitleaks version`, `checkov --version`)
- Platform: `uname -s` + `uname -m`
- Package managers: check for `brew`, `pip3`, `cargo`, `apt-get`, `go`

### commands/doctor.md

Markdown command that instructs Claude to:
1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh`
2. Parse the JSON output
3. Present a human-readable status table with fail mode for each scanner
4. For missing tools, provide platform-appropriate install commands based on detected package managers
5. Briefly explain what each scanner does

## Escape Hatches

No custom `.seatbeltignore` format. Each tool's native ignore mechanism is respected and documented in block messages.

| Scanner | Persistent suppression | One-time bypass |
|---------|----------------------|-----------------|
| gitleaks | `.gitleaksignore` (allowlist by fingerprint) | `SKIP_GITLEAKS=1` |
| checkov | `#checkov:skip=CKV_XXX:reason` inline or `.checkov.yml` | `SKIP_CHECKOV=1` |
| trivy | `.trivyignore` (CVE IDs) | `SKIP_TRIVY=1` |
| zizmor | Per-rule config in workflow file | `SKIP_ZIZMOR=1` |
| All | — | `SKIP_SEATBELT=1` |

## plugin.json

```json
{
  "name": "seatbelt",
  "version": "1.0.0",
  "description": "Zero-config security scanning for vibe coders. Bundles gitleaks, checkov, trivy, and zizmor as pre-commit hooks.",
  "author": {
    "name": "seatbelt contributors"
  },
  "license": "MIT",
  "repository": "https://github.com/seatbelt-dev/seatbelt",
  "keywords": ["security", "scanning", "hooks", "gitleaks", "checkov", "trivy", "zizmor", "vibe-coding"]
}
```

## What's NOT in v1

| Feature | Why deferred |
|---------|-------------|
| Remediation skill | Hook block messages are the remediation surface. Avoids "suppression copilot" behavior and context token cost. Add `/seatbelt explain` in v1.1 if users still struggle. |
| `/seatbelt status` | Nice-to-have visibility, not essential for core value. v2. |
| SessionStart health check | Wrong moment — fires when user isn't committing, trains users to ignore warnings. |
| Auto-install of tools | Doctor provides guidance, user decides. Auto-installing binaries from a security plugin is opinionated and surprising. |
| Binary bundling | v2 architecture for true zero-config. Impractical in v1 (checkov is a large Python package). |
| Custom `.seatbeltignore` | Each tool has its own well-documented ignore format. A translation layer adds complexity and drifts when upstream tools change. |
| Standalone CLI | Codex CLI suggestion for broader reach. Right v2 architecture but requires more engineering. |

## Dependencies

**Required by hook scripts:**
- `bash` — scripts use `#!/usr/bin/env bash` shebang and avoid bash 4+ features (no associative arrays, no `${var,,}` lowercasing). Compatible with macOS stock bash 3.2 and Linux bash 4+/5+.
- `git` (for `git diff --cached`, `git rev-parse`)

**Required for JSON parsing in hooks:**
- `python3` — if missing, hooks skip gracefully (fail-open). Fast case-match pre-filter catches most non-commit calls without python3.

**Required by scanner scripts (each scanner is independent):**
- `gitleaks` — for secret scanning
- `checkov` — for IaC scanning (supports `checkov` binary or `python3 -m checkov.main`)
- `trivy` — for dependency CVE scanning (requires cached vulnerability DB)
- `zizmor` — for GH Actions security scanning

**Required by doctor.sh:**
- `bash`, `uname`
- No python3 required (uses bash-native detection)

## Platform Support

- **macOS (arm64, x64):** Primary development platform. All tools available via Homebrew.
- **Linux (x64, arm64):** Must work. Tools available via apt, pip, cargo, or direct download.
- **Windows:** Not supported in v1. Claude Code on Windows uses WSL, which falls under Linux support.

## Competitive Landscape

| Product | Type | Seatbelt's differentiation |
|---------|------|---------------------------|
| Prismatic | OSS CLI (Go) | Same tools, but targets DevSecOps. No Claude Code integration. |
| Legit VibeGuard | Commercial SaaS | IDE-level for Cursor/Copilot. No Claude Code. Needs registration. |
| Codacy Guardrails | Commercial SaaS | Cursor/Copilot only. Needs registration. |
| MegaLinter | OSS mega-linter | 50+ languages, heavy. Not vibe-coder focused. |
| pre-commit framework | OSS hook runner | Individual tool hooks exist but no bundling, no Claude Code. |

Seatbelt fills the gap: zero-registration bundled scanner specifically for Claude Code's hook architecture.

## SKIP Env Var Behavior

`SKIP_*` env vars must be set in the **hook process environment**, not inline in the git commit command. Hooks run as separate processes invoked by Claude Code before the command executes — they inherit Claude Code's environment, which inherits from the user's shell.

**Correct bypass:**
```bash
export SKIP_GITLEAKS=1    # Set in user's shell (persists until unset)
# Claude Code hooks will now see this env var
```

**Incorrect (does not work):**
```bash
SKIP_GITLEAKS=1 git commit -m "fix"    # Sets var for git, not for the hook
```

Block messages instruct users to `export SKIP_*=1` in their shell, then retry.

## Known v1 Limitations

| Limitation | Impact | Planned resolution |
|-----------|--------|-------------------|
| Scanners read working directory, not git index | If staged version differs from working directory, scanner evaluates the wrong version | v2: Extract staged contents via `git show :file` to temp dir |
| Checkov file patterns are path-based, not content-based | Kubernetes manifests outside `k8s/` dirs, `compose.yaml` (without `docker-compose` prefix), and Helm charts outside `helm/` dirs are not scanned | v2: Content sniffing for `apiVersion`/`kind` YAML fields |
| Trivy/zizmor output parsed via grep, not structured JSON | Fragile across tool version changes | v1.1: Use `--format json` / `--format sarif` where available |
| Commit detection misses path-prefixed git | `/usr/bin/git commit`, `git -C repo commit` bypass hooks | Rare in Claude Code tool calls; accepted for v1 |
| "Zero-config" requires external tool installation | Fresh install has no scanners — all degraded | v2: Binary bundling or container-based scanning |

## Testing Strategy

Hooks are bash scripts triggered by Claude Code's internal hook system. Testing requires fixture-based validation:

**Unit tests (per-script):**
- Fixture JSON payloads simulating PreToolUse stdin for various commands (`git commit`, `npm install`, `git push`, chained commands)
- Expected: correct commit detection (true positive + true negative)
- Fixture scanner outputs for each fail mode (finding, clean, tool error, missing tool)
- Expected: correct block/warn/pass behavior per fail mode

**Integration tests:**
- Pipe fixture JSON into each script, verify stdout/stderr output
- Test with scanner binary present and absent (mock via PATH manipulation)
- Test SKIP env vars (set → verify skip; unset → verify scan runs)
- Test block_emit() JSON validity with multi-line, quote-containing messages

**Platform tests (CI):**
- macOS (arm64) + Linux (x64) runners
- bash 3.2 (macOS stock) and bash 5+ (Linux)
- With and without jq installed (block_emit fallback)
- With and without python3 (graceful degradation)

**Test fixtures location:** `tests/fixtures/` with sample hook JSON payloads and scanner outputs.
