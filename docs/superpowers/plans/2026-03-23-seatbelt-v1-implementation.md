<!-- design-reviewed: PASS -->

# Seatbelt v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Seatbelt Claude Code plugin — 4 security scanner hooks + doctor command — from the approved design spec.

**Architecture:** 4 independent bash hook scripts (no shared library), each self-contained with inline commit detection, scanner invocation, and block/warn emission. One doctor command (bash script + markdown command file). Plugin manifest wires everything together.

**Tech Stack:** Bash (3.2+ compatible), python3 (inline JSON parsing), Claude Code plugin system (hooks.json, plugin.json, commands/)

**Spec:** `docs/superpowers/specs/2026-03-23-seatbelt-v1-design.md`

**Reference implementations:** `~/.claude/hooks/pre-commit-gitleaks.sh` and `~/.claude/hooks/pre-commit-iac-scan.sh` — these are working scripts that need adaptation for the plugin structure.

---

### Task 1: Plugin Scaffold

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `hooks/hooks.json`
- Create: `LICENSE`

- [ ] **Step 1: Create plugin manifest**

```bash
mkdir -p .claude-plugin
```

Write `.claude-plugin/plugin.json`:
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

- [ ] **Step 2: Create hooks.json**

```bash
mkdir -p hooks/scripts
```

Write `hooks/hooks.json`:
```json
{
  "hooks": [
    {
      "type": "PreToolUse",
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-gitleaks.sh\""
        }
      ]
    },
    {
      "type": "PreToolUse",
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-checkov.sh\""
        }
      ]
    },
    {
      "type": "PreToolUse",
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-trivy.sh\""
        }
      ]
    },
    {
      "type": "PreToolUse",
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/scan-zizmor.sh\""
        }
      ]
    }
  ]
}
```

- [ ] **Step 3: Create LICENSE (MIT)**

Write `LICENSE` with MIT license text, copyright "seatbelt contributors".

- [ ] **Step 4: Commit scaffold**

```bash
git add .claude-plugin/plugin.json hooks/hooks.json LICENSE
git commit -m "feat: add plugin scaffold (plugin.json, hooks.json, LICENSE)"
```

---

### Task 2: Test Framework + Commit Detection Fixtures

**Files:**
- Create: `tests/run-tests.sh`
- Create: `tests/fixtures/git-commit.json`
- Create: `tests/fixtures/git-commit-amend.json`
- Create: `tests/fixtures/git-commit-chained.json`
- Create: `tests/fixtures/npm-install.json`
- Create: `tests/fixtures/git-push.json`
- Create: `tests/fixtures/grep-git-commit.json`

The test framework pipes fixture JSON into hook scripts and asserts on stdout/stderr/exit code. Tests run without any scanner binaries installed (they test the commit detection and degraded-mode paths).

- [ ] **Step 1: Create test fixtures**

Write `tests/fixtures/git-commit.json`:
```json
{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add feature\""}}
```

Write `tests/fixtures/git-commit-amend.json`:
```json
{"tool_name":"Bash","tool_input":{"command":"git commit --amend --no-edit"}}
```

Write `tests/fixtures/git-commit-chained.json`:
```json
{"tool_name":"Bash","tool_input":{"command":"git add -A && git commit -m \"chore: update\""}}
```

Write `tests/fixtures/npm-install.json`:
```json
{"tool_name":"Bash","tool_input":{"command":"npm install express"}}
```

Write `tests/fixtures/git-push.json`:
```json
{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}
```

Write `tests/fixtures/grep-git-commit.json`:
```json
{"tool_name":"Bash","tool_input":{"command":"grep -r 'git commit' docs/"}}
```

Write `tests/fixtures/git-commit-camelcase.json` (tests `toolName`/`toolInput` variant):
```json
{"toolName":"Bash","toolInput":{"command":"git commit -m \"feat: camelCase fields\""}}
```

Write `tests/fixtures/git-commit-env-prefix.json` (tests env var prefix stripping):
```json
{"tool_name":"Bash","tool_input":{"command":"SKIP_GITLEAKS=1 git commit -m \"bypass\""}}
```

- [ ] **Step 2: Create test runner**

Write `tests/run-tests.sh` — a bash test framework that:
1. Sources test files from `tests/test-*.sh`
2. Tracks pass/fail counts
3. Provides assertion helpers: `assert_exit_0`, `assert_stdout_empty`, `assert_stdout_contains`, `assert_stderr_contains`, `assert_stdout_json_block`
4. Runs each test function in a subshell for isolation
5. Manipulates PATH to mock missing scanner binaries

```bash
#!/usr/bin/env bash
# Seatbelt test runner
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
FIXTURES_DIR="$TESTS_DIR/fixtures"

PASS=0
FAIL=0
ERRORS=""

# Colors (if terminal supports it)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# ── Assertion helpers ────────────────────────────────────────────────
assert_exit_0() {
    if [ "$EXIT_CODE" -ne 0 ]; then
        ERRORS="${ERRORS}\n  Expected exit 0, got $EXIT_CODE"
        return 1
    fi
}

assert_stdout_empty() {
    if [ -n "$STDOUT" ]; then
        ERRORS="${ERRORS}\n  Expected empty stdout, got: $STDOUT"
        return 1
    fi
}

assert_stdout_contains() {
    if ! echo "$STDOUT" | grep -qF "$1"; then
        ERRORS="${ERRORS}\n  Expected stdout to contain '$1'"
        return 1
    fi
}

assert_stderr_contains() {
    if ! echo "$STDERR" | grep -qF "$1"; then
        ERRORS="${ERRORS}\n  Expected stderr to contain '$1'"
        return 1
    fi
}

assert_stdout_json_block() {
    if ! echo "$STDOUT" | grep -qF '"decision":"block"'; then
        ERRORS="${ERRORS}\n  Expected stdout to contain block decision JSON"
        return 1
    fi
}

assert_stdout_no_block() {
    if echo "$STDOUT" | grep -qF '"decision":"block"'; then
        ERRORS="${ERRORS}\n  Expected stdout NOT to contain block decision JSON"
        return 1
    fi
}

# ── Run a single test ────────────────────────────────────────────────
# Usage: run_test "test name" script_path fixture_path [env_vars...]
run_hook_test() {
    local name="$1"
    local script="$2"
    local fixture="$3"
    shift 3

    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0

    # Run the hook script with fixture as stdin, capturing stdout and stderr
    local tmpout tmpeer
    tmpout=$(mktemp)
    tmperr=$(mktemp)

    (
        # Apply any env var overrides
        for var in "$@"; do
            export "$var"
        done
        cat "$fixture" | bash "$script" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?

    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr"
}

# ── Report helpers ───────────────────────────────────────────────────
pass() {
    PASS=$((PASS + 1))
    printf "${GREEN}  PASS${NC} %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL${NC} %s%b\n" "$1" "$ERRORS"
}

# ── Degraded-mode PATH helper ────────────────────────────────────────
# Creates a temp bin dir with only essential tools (bash, python3, git, etc.)
# so scanner binaries are guaranteed hidden regardless of install location.
make_degraded_path() {
    local tmpbin
    tmpbin=$(mktemp -d)
    for cmd in bash python3 git uname cat grep sed head printf tr ls mkdir rm mktemp sort; do
        local p
        p=$(command -v "$cmd" 2>/dev/null || true)
        [ -n "$p" ] && ln -sf "$p" "$tmpbin/$cmd"
    done
    echo "$tmpbin"
}

# ── Run all test files ───────────────────────────────────────────────
echo "=== Seatbelt Test Suite ==="
echo ""

for test_file in "$TESTS_DIR"/test-*.sh; do
    [ -f "$test_file" ] || continue
    echo "--- $(basename "$test_file") ---"
    source "$test_file"
done

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 3: Verify test runner is executable**

```bash
chmod +x tests/run-tests.sh
bash tests/run-tests.sh
```

Expected: `=== Results: 0 passed, 0 failed ===` (no test files yet)

- [ ] **Step 4: Commit test framework**

```bash
git add tests/
git commit -m "test: add test framework and fixture JSON payloads"
```

---

### Task 3: scan-gitleaks.sh

**Files:**
- Create: `hooks/scripts/scan-gitleaks.sh`
- Create: `tests/test-gitleaks.sh`

Adapted from `~/.claude/hooks/pre-commit-gitleaks.sh`. Changes: updated SKIP env var name (SKIP_GITLEAKS + SKIP_SEATBELT), updated block message format per spec, added degraded-mode warning when gitleaks not installed.

- [ ] **Step 1: Write test file**

Write `tests/test-gitleaks.sh`:
```bash
# Tests for scan-gitleaks.sh
GITLEAKS_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-gitleaks.sh"

# ── Commit detection tests ──────────────────────────────────────────

test_gitleaks_skips_npm_install() {
    run_hook_test "skip npm install" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    assert_exit_0 && assert_stdout_empty && pass "skips npm install" || fail "skips npm install"
}
test_gitleaks_skips_npm_install

test_gitleaks_skips_git_push() {
    run_hook_test "skip git push" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-push.json"
    assert_exit_0 && assert_stdout_empty && pass "skips git push" || fail "skips git push"
}
test_gitleaks_skips_git_push

test_gitleaks_skips_grep_git_commit() {
    run_hook_test "skip grep git commit" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/grep-git-commit.json"
    assert_exit_0 && assert_stdout_empty && pass "skips grep git commit" || fail "skips grep git commit"
}
test_gitleaks_skips_grep_git_commit

# ── Skip env var tests ──────────────────────────────────────────────

test_gitleaks_skip_var() {
    run_hook_test "SKIP_GITLEAKS" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_GITLEAKS=1"
    assert_exit_0 && assert_stdout_empty && pass "SKIP_GITLEAKS=1 skips" || fail "SKIP_GITLEAKS=1 skips"
}
test_gitleaks_skip_var

test_gitleaks_skip_seatbelt() {
    run_hook_test "SKIP_SEATBELT" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    assert_exit_0 && assert_stdout_empty && pass "SKIP_SEATBELT=1 skips" || fail "SKIP_SEATBELT=1 skips"
}
test_gitleaks_skip_seatbelt

# ── Degraded mode test (gitleaks not in PATH) ───────────────────────

test_gitleaks_degraded() {
    # Create a temp PATH with only essential tools — no scanner binaries
    local SAFE_PATH
    SAFE_PATH=$(make_degraded_path)
    run_hook_test "degraded" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-commit.json" "PATH=${SAFE_PATH}"
    assert_exit_0 && assert_stdout_empty && assert_stderr_contains "SEATBELT DEGRADED" && pass "degraded warning" || fail "degraded warning"
}
test_gitleaks_degraded

# ── camelCase field name tests ──────────────────────────────────────

test_gitleaks_camelcase_fields() {
    local SAFE_PATH
    SAFE_PATH=$(make_degraded_path)
    run_hook_test "camelCase fields" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-commit-camelcase.json" "PATH=${SAFE_PATH}"
    assert_exit_0 && assert_stderr_contains "SEATBELT DEGRADED" && pass "handles camelCase fields" || fail "handles camelCase fields"
}
test_gitleaks_camelcase_fields

# ── amend and chained command tests ─────────────────────────────────

test_gitleaks_detects_amend() {
    local SAFE_PATH
    SAFE_PATH=$(make_degraded_path)
    run_hook_test "amend" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-commit-amend.json" "PATH=${SAFE_PATH}"
    assert_exit_0 && assert_stderr_contains "SEATBELT DEGRADED" && pass "detects git commit --amend" || fail "detects git commit --amend"
}
test_gitleaks_detects_amend

test_gitleaks_detects_chained() {
    local SAFE_PATH
    SAFE_PATH=$(make_degraded_path)
    run_hook_test "chained" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-commit-chained.json" "PATH=${SAFE_PATH}"
    assert_exit_0 && assert_stderr_contains "SEATBELT DEGRADED" && pass "detects chained git commit" || fail "detects chained git commit"
}
test_gitleaks_detects_chained

test_gitleaks_detects_env_prefix() {
    local SAFE_PATH
    SAFE_PATH=$(make_degraded_path)
    run_hook_test "env prefix" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-commit-env-prefix.json" "PATH=${SAFE_PATH}"
    assert_exit_0 && assert_stderr_contains "SEATBELT DEGRADED" && pass "detects VAR=1 git commit" || fail "detects VAR=1 git commit"
}
test_gitleaks_detects_env_prefix
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash tests/run-tests.sh
```

Expected: FAIL (script doesn't exist yet)

- [ ] **Step 3: Write scan-gitleaks.sh**

Write `hooks/scripts/scan-gitleaks.sh`:
```bash
#!/usr/bin/env bash
# Seatbelt: scan staged changes for secrets before git commit
# Scanner: gitleaks | Fail mode: BLOCK on findings, fail-open on errors
# Skip: SKIP_GITLEAKS=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Block emission helper ────────────────────────────────────────────
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

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_GITLEAKS:-0}" = "1" ] && exit 0

# ── Consume stdin ───────────────────────────────────────────────────
HOOK_DATA=$(cat 2>/dev/null || true)
[ -z "$HOOK_DATA" ] && exit 0

# ── Fast pre-filter ─────────────────────────────────────────────────
case "$HOOK_DATA" in
    *\"Bash\"*git\ commit*) ;;
    *git\ commit*\"Bash\"*) ;;
    *) exit 0 ;;
esac

# ── python3 JSON parsing ───────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    exit 0  # fail-open without python3
fi

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

# Not in a git repo → skip
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# ── gitleaks availability ───────────────────────────────────────────
if ! command -v gitleaks &>/dev/null; then
    echo "SEATBELT DEGRADED: gitleaks not installed — secret scanning DISABLED (brew install gitleaks | /seatbelt doctor)" >&2
    exit 0
fi

# ── Run gitleaks ────────────────────────────────────────────────────
GITLEAKS_EXIT=0
GITLEAKS_OUTPUT=$(gitleaks protect --staged --no-banner 2>&1) || GITLEAKS_EXIT=$?

# Exit 0 = clean
[ "$GITLEAKS_EXIT" -eq 0 ] && exit 0

# Exit 1 = findings → BLOCK
if [ "$GITLEAKS_EXIT" -eq 1 ]; then
    TRUNCATED=$(echo "$GITLEAKS_OUTPUT" | head -20)
    REASON="SECRET DETECTED in staged changes — commit blocked.

Gitleaks found potential secrets/credentials:

${TRUNCATED}

Fix: Remove the secret from staged files. Use environment variables or a secret manager.
False positive? Add the fingerprint to .gitleaksignore
Bypass once: export SKIP_GITLEAKS=1 in your shell, then retry"
    block_emit "$REASON"
    exit 0
fi

# Other exit codes = tool error → pass through (fail-open)
exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x hooks/scripts/scan-gitleaks.sh
bash tests/run-tests.sh
```

Expected: All gitleaks tests PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/scan-gitleaks.sh tests/test-gitleaks.sh
git commit -m "feat: add scan-gitleaks.sh with tests"
```

---

### Task 4: scan-checkov.sh

**Files:**
- Create: `hooks/scripts/scan-checkov.sh`
- Create: `tests/test-checkov.sh`

Extracted from the checkov section of `~/.claude/hooks/pre-commit-iac-scan.sh`. Made standalone with SKIP_CHECKOV env var, rich block messages, and parse-errors-as-warn.

- [ ] **Step 1: Write test file**

Write `tests/test-checkov.sh`:
```bash
# Tests for scan-checkov.sh
CHECKOV_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-checkov.sh"

test_checkov_skips_npm_install() {
    run_hook_test "skip npm install" "$CHECKOV_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    assert_exit_0 && assert_stdout_empty && pass "checkov skips npm install" || fail "checkov skips npm install"
}
test_checkov_skips_npm_install

test_checkov_skip_var() {
    run_hook_test "SKIP_CHECKOV" "$CHECKOV_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_CHECKOV=1"
    assert_exit_0 && assert_stdout_empty && pass "SKIP_CHECKOV=1 skips" || fail "SKIP_CHECKOV=1 skips"
}
test_checkov_skip_var

test_checkov_skip_seatbelt() {
    run_hook_test "SKIP_SEATBELT" "$CHECKOV_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    assert_exit_0 && assert_stdout_empty && pass "SKIP_SEATBELT=1 skips checkov" || fail "SKIP_SEATBELT=1 skips checkov"
}
test_checkov_skip_seatbelt

test_checkov_degraded() {
    local SAFE_PATH
    SAFE_PATH=$(make_degraded_path)
    run_hook_test "degraded" "$CHECKOV_SCRIPT" "$FIXTURES_DIR/git-commit.json" "PATH=${SAFE_PATH}"
    assert_exit_0 && assert_stdout_empty && assert_stderr_contains "SEATBELT DEGRADED" && pass "checkov degraded warning" || fail "checkov degraded warning"
}
test_checkov_degraded
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash tests/run-tests.sh
```

Expected: FAIL (script doesn't exist)

- [ ] **Step 3: Write scan-checkov.sh**

Write `hooks/scripts/scan-checkov.sh` — complete script identical to scan-gitleaks.sh structure (inline block_emit, inline python3 parsing, SKIP vars, degraded warning) but with checkov-specific logic:

- Detect checkov binary or `python3 -m checkov.main` fallback
- Collect staged files, match against framework case table (Dockerfile, .tf, docker-compose, github_actions, k8s, helm)
- Run `checkov --file <file> --framework <framework> --compact --quiet` per matched file
- FAILED checks → BLOCK via block_emit() with CKV rule details, truncated to 3 lines
- Parse errors → warn (stderr), not block (consistent with fail-open-on-errors)
- Rich block message: what was found, fix, suppress (#checkov:skip=CKV_XXX:reason), bypass (export SKIP_CHECKOV=1)

**The complete ~110-line script follows the exact same template as scan-gitleaks.sh above** — copy the full shared pattern (lines 1-78 of scan-gitleaks.sh), then replace the scanner-specific section (lines 79-end) with the checkov logic. The shared pattern is identical across all 4 scripts: shebang, set -euo, ERR trap, block_emit(), SKIP checks, consume stdin, case pre-filter, python3 parsing, git repo check. Only the scanner section differs.

**Scanner section for checkov (replaces gitleaks section):**
```bash
# ── checkov availability ────────────────────────────────────────────
CHECKOV_CMD=""
if command -v checkov &>/dev/null; then
    CHECKOV_CMD="checkov"
elif python3 -c "import checkov" &>/dev/null 2>&1; then
    CHECKOV_CMD="python3 -m checkov.main"
fi

if [ -z "$CHECKOV_CMD" ]; then
    echo "SEATBELT DEGRADED: checkov not installed — IaC scanning DISABLED (pip3 install checkov | /seatbelt doctor)" >&2
    exit 0
fi

# ── Collect staged IaC files ────────────────────────────────────────
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
[ -z "$STAGED_FILES" ] && exit 0

BLOCKED=0
BLOCK_DETAILS=""

while IFS= read -r staged_file; do
    [ -z "$staged_file" ] && continue
    [ -f "$staged_file" ] || continue

    FRAMEWORK=""
    case "$staged_file" in
        *Dockerfile*|*dockerfile*)                              FRAMEWORK="dockerfile" ;;
        *.tf|*.tf.json)                                         FRAMEWORK="terraform" ;;
        *docker-compose*.yml|*docker-compose*.yaml)             FRAMEWORK="docker_compose" ;;
        .github/workflows/*.yml|.github/workflows/*.yaml)       FRAMEWORK="github_actions" ;;
        *k8s*/*.yml|*k8s*/*.yaml|*kubernetes*/*.yml|*kubernetes*/*.yaml) FRAMEWORK="kubernetes" ;;
        *helm*/*.yml|*helm*/*.yaml)                             FRAMEWORK="helm" ;;
        *)                                                      continue ;;
    esac

    OUTPUT=$($CHECKOV_CMD --file "$staged_file" --framework "$FRAMEWORK" --compact --quiet 2>&1) || true
    FAILED=$(echo "$OUTPUT" | grep -c "FAILED" 2>/dev/null || true)
    FAILED=${FAILED:-0}
    PARSE_ERRORS=$(echo "$OUTPUT" | grep -cE "Parsing errors:" 2>/dev/null || true)
    PARSE_ERRORS=${PARSE_ERRORS:-0}

    if [ "$FAILED" -gt 0 ]; then
        BLOCKED=1
        BLOCK_DETAILS="${BLOCK_DETAILS}$(echo "$OUTPUT" | grep "FAILED" | head -3)\n"
    elif [ "$PARSE_ERRORS" -gt 0 ]; then
        echo "SEATBELT: checkov parse error in $(basename "$staged_file") — skipping" >&2
    fi
done <<< "$STAGED_FILES"

if [ "$BLOCKED" = "1" ]; then
    REASON="IaC MISCONFIGURATION in staged files — commit blocked.

checkov found failed checks:

$(printf '%b' "$BLOCK_DETAILS")

Fix: Address the failed checks listed above.
False positive? Add #checkov:skip=CKV_XXX:reason above the affected line
Bypass once: export SKIP_CHECKOV=1 in your shell, then retry"
    block_emit "$REASON"
fi

exit 0
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x hooks/scripts/scan-checkov.sh
bash tests/run-tests.sh
```

Expected: All checkov tests PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/scan-checkov.sh tests/test-checkov.sh
git commit -m "feat: add scan-checkov.sh with tests"
```

---

### Task 5: scan-trivy.sh

**Files:**
- Create: `hooks/scripts/scan-trivy.sh`
- Create: `tests/test-trivy.sh`

Extracted from the trivy section of `~/.claude/hooks/pre-commit-iac-scan.sh`. Made standalone with SKIP_TRIVY env var. Warn-only (no block). Includes DB existence check and portable timeout.

- [ ] **Step 1: Write test file**

Write `tests/test-trivy.sh`:
```bash
# Tests for scan-trivy.sh
TRIVY_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-trivy.sh"

test_trivy_skips_npm_install() {
    run_hook_test "skip npm install" "$TRIVY_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    assert_exit_0 && assert_stdout_empty && pass "trivy skips npm install" || fail "trivy skips npm install"
}
test_trivy_skips_npm_install

test_trivy_skip_var() {
    run_hook_test "SKIP_TRIVY" "$TRIVY_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_TRIVY=1"
    assert_exit_0 && assert_stdout_empty && pass "SKIP_TRIVY=1 skips" || fail "SKIP_TRIVY=1 skips"
}
test_trivy_skip_var

test_trivy_skip_seatbelt() {
    run_hook_test "SKIP_SEATBELT" "$TRIVY_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    assert_exit_0 && assert_stdout_empty && pass "SKIP_SEATBELT=1 skips trivy" || fail "SKIP_SEATBELT=1 skips trivy"
}
test_trivy_skip_seatbelt

test_trivy_degraded() {
    local SAFE_PATH
    SAFE_PATH=$(make_degraded_path)
    run_hook_test "degraded" "$TRIVY_SCRIPT" "$FIXTURES_DIR/git-commit.json" "PATH=${SAFE_PATH}"
    assert_exit_0 && assert_stdout_empty && assert_stderr_contains "SEATBELT DEGRADED" && pass "trivy degraded warning" || fail "trivy degraded warning"
}
test_trivy_degraded

test_trivy_never_blocks() {
    # trivy is warn-only — stdout must never contain block decision
    run_hook_test "never blocks" "$TRIVY_SCRIPT" "$FIXTURES_DIR/git-commit.json"
    assert_exit_0 && assert_stdout_no_block && pass "trivy never blocks" || fail "trivy never blocks"
}
test_trivy_never_blocks
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bash tests/run-tests.sh
```

- [ ] **Step 3: Write scan-trivy.sh**

Write `hooks/scripts/scan-trivy.sh` — same shared pattern as scan-gitleaks.sh (copy lines 1-78), then replace scanner section with:

**Scanner section for trivy (warn-only, never blocks):**
```bash
# ── trivy availability ──────────────────────────────────────────────
if ! command -v trivy &>/dev/null; then
    echo "SEATBELT DEGRADED: trivy not installed — dependency CVE scanning DISABLED (brew install trivy | /seatbelt doctor)" >&2
    exit 0
fi

# ── Collect staged lock files ───────────────────────────────────────
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
[ -z "$STAGED_FILES" ] && exit 0

LOCKFILES=$(echo "$STAGED_FILES" | grep -E '(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|requirements\.txt|poetry\.lock|uv\.lock|Pipfile\.lock|go\.sum|Gemfile\.lock|composer\.lock)$' || true)
[ -z "$LOCKFILES" ] && exit 0

# ── Check trivy DB cache ───────────────────────────────────────────
TRIVY_CACHE="${TRIVY_CACHE_DIR:-}"
if [ -z "$TRIVY_CACHE" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        TRIVY_CACHE="${HOME}/Library/Caches/trivy/db"
    else
        TRIVY_CACHE="${HOME}/.cache/trivy/db"
    fi
else
    TRIVY_CACHE="${TRIVY_CACHE}/db"
fi

if [ ! -d "$TRIVY_CACHE" ] || [ -z "$(ls -A "$TRIVY_CACHE" 2>/dev/null)" ]; then
    echo "SEATBELT: trivy: no vulnerability DB cached — run 'trivy image --download-db-only' to enable dep scanning" >&2
    exit 0
fi

# ── Portable timeout ───────────────────────────────────────────────
TIMEOUT_CMD=""
if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout 30"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout 30"
fi

# ── Scan lock files (warn only) ────────────────────────────────────
while IFS= read -r lf; do
    [ -f "$lf" ] || continue
    OUTPUT=$($TIMEOUT_CMD trivy fs --scanners vuln --severity HIGH,CRITICAL --skip-db-update --no-progress "$lf" 2>/dev/null) || true
    HAS_VULNS=$(echo "$OUTPUT" | grep -E "Total: [1-9]" 2>/dev/null || true)
    if [ -n "$HAS_VULNS" ]; then
        echo "SEATBELT: trivy found vulnerabilities in $(basename "$lf"):" >&2
        echo "$OUTPUT" | grep -E "(HIGH|CRITICAL)" | head -5 >&2
    fi
done <<< "$LOCKFILES"

exit 0
```

**Note:** This script NEVER emits `{"decision":"block"}` — trivy is warn-only. All output goes to stderr. The ERR trap is `exit 0` (fail-open). No block_emit() function needed (but included for template consistency — it's just unused).

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x hooks/scripts/scan-trivy.sh
bash tests/run-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/scan-trivy.sh tests/test-trivy.sh
git commit -m "feat: add scan-trivy.sh with tests"
```

---

### Task 6: scan-zizmor.sh

**Files:**
- Create: `hooks/scripts/scan-zizmor.sh`
- Create: `tests/test-zizmor.sh`

Extracted from the zizmor section of `~/.claude/hooks/pre-commit-iac-scan.sh`. Made standalone with SKIP_ZIZMOR env var. Warn-only.

- [ ] **Step 1: Write test file**

Write `tests/test-zizmor.sh`:
```bash
# Tests for scan-zizmor.sh
ZIZMOR_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-zizmor.sh"

test_zizmor_skips_npm_install() {
    run_hook_test "skip npm install" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    assert_exit_0 && assert_stdout_empty && pass "zizmor skips npm install" || fail "zizmor skips npm install"
}
test_zizmor_skips_npm_install

test_zizmor_skip_var() {
    run_hook_test "SKIP_ZIZMOR" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_ZIZMOR=1"
    assert_exit_0 && assert_stdout_empty && pass "SKIP_ZIZMOR=1 skips" || fail "SKIP_ZIZMOR=1 skips"
}
test_zizmor_skip_var

test_zizmor_skip_seatbelt() {
    run_hook_test "SKIP_SEATBELT" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    assert_exit_0 && assert_stdout_empty && pass "SKIP_SEATBELT=1 skips zizmor" || fail "SKIP_SEATBELT=1 skips zizmor"
}
test_zizmor_skip_seatbelt

test_zizmor_degraded() {
    local SAFE_PATH
    SAFE_PATH=$(make_degraded_path)
    run_hook_test "degraded" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/git-commit.json" "PATH=${SAFE_PATH}"
    assert_exit_0 && assert_stdout_empty && assert_stderr_contains "SEATBELT DEGRADED" && pass "zizmor degraded warning" || fail "zizmor degraded warning"
}
test_zizmor_degraded

test_zizmor_never_blocks() {
    run_hook_test "never blocks" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/git-commit.json"
    assert_exit_0 && assert_stdout_no_block && pass "zizmor never blocks" || fail "zizmor never blocks"
}
test_zizmor_never_blocks
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Write scan-zizmor.sh**

Write `hooks/scripts/scan-zizmor.sh` — same shared pattern as scan-gitleaks.sh (copy lines 1-78), then replace scanner section with:

**Scanner section for zizmor (warn-only, never blocks):**
```bash
# ── zizmor availability ─────────────────────────────────────────────
if ! command -v zizmor &>/dev/null; then
    echo "SEATBELT DEGRADED: zizmor not installed — GitHub Actions scanning DISABLED (pip3 install zizmor | /seatbelt doctor)" >&2
    exit 0
fi

# ── Collect staged workflow files ───────────────────────────────────
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
[ -z "$STAGED_FILES" ] && exit 0

WORKFLOW_FILES=$(echo "$STAGED_FILES" | grep -E '\.github/workflows/.*\.(yml|yaml)$' || true)
[ -z "$WORKFLOW_FILES" ] && exit 0

# ── Scan workflow files (warn only) ─────────────────────────────────
while IFS= read -r wf; do
    [ -f "$wf" ] || continue
    OUTPUT=$(zizmor --no-progress "$wf" 2>&1) || true
    if echo "$OUTPUT" | grep -qE '(warning|error)\['; then
        HITS=$(echo "$OUTPUT" | grep -cE '(warning|error)\[' 2>/dev/null || echo "0")
        echo "SEATBELT: zizmor found ${HITS} issue(s) in $(basename "$wf"):" >&2
        echo "$OUTPUT" | grep -E '(warning|error)\[' | head -3 >&2
    fi
done <<< "$WORKFLOW_FILES"

exit 0
```

**Note:** Like trivy, this script NEVER emits `{"decision":"block"}`. All output goes to stderr. Warn-only by design.

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x hooks/scripts/scan-zizmor.sh
bash tests/run-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add hooks/scripts/scan-zizmor.sh tests/test-zizmor.sh
git commit -m "feat: add scan-zizmor.sh with tests"
```

---

### Task 7: doctor.sh

**Files:**
- Create: `scripts/doctor.sh`
- Create: `tests/test-doctor.sh`

Deterministic bash script that outputs JSON with tool presence, versions, platform, and package managers. No python3 dependency.

- [ ] **Step 1: Write test file**

Write `tests/test-doctor.sh`:
```bash
# Tests for doctor.sh
DOCTOR_SCRIPT="$PROJECT_ROOT/scripts/doctor.sh"

test_doctor_outputs_valid_json() {
    EXIT_CODE=0
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null) || EXIT_CODE=$?
    ERRORS=""
    if [ "$EXIT_CODE" -ne 0 ]; then
        ERRORS="\n  doctor.sh exited with $EXIT_CODE"
        fail "doctor outputs valid JSON"
        return
    fi
    # Validate JSON structure
    if ! echo "$STDOUT" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        ERRORS="\n  doctor.sh output is not valid JSON: $STDOUT"
        fail "doctor outputs valid JSON"
        return
    fi
    pass "doctor outputs valid JSON"
}
test_doctor_outputs_valid_json

test_doctor_has_platform() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    if ! echo "$STDOUT" | python3 -c "import sys, json; d=json.load(sys.stdin); assert 'platform' in d" 2>/dev/null; then
        ERRORS="\n  doctor output missing 'platform' field"
        fail "doctor has platform"
        return
    fi
    pass "doctor has platform"
}
test_doctor_has_platform

test_doctor_has_all_scanners() {
    STDOUT=$(bash "$DOCTOR_SCRIPT" 2>/dev/null)
    ERRORS=""
    for tool in gitleaks checkov trivy zizmor; do
        if ! echo "$STDOUT" | python3 -c "import sys, json; d=json.load(sys.stdin); assert '$tool' in d" 2>/dev/null; then
            ERRORS="\n  doctor output missing '$tool' field"
            fail "doctor has all scanners"
            return
        fi
    done
    pass "doctor has all scanners"
}
test_doctor_has_all_scanners
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Write doctor.sh**

Write `scripts/doctor.sh`:
```bash
#!/usr/bin/env bash
# Seatbelt doctor: detect installed scanners and report status as JSON
set -euo pipefail

# ── Helper: check tool and get version ──────────────────────────────
check_tool() {
    local name="$1"
    local version_cmd="$2"
    local path=""
    local version=""
    local installed=false

    path=$(command -v "$name" 2>/dev/null || true)
    if [ -n "$path" ]; then
        installed=true
        version=$(eval "$version_cmd" 2>/dev/null | head -1 || true)
    fi

    # checkov fallback: python3 -m checkov
    if [ "$installed" = "false" ] && [ "$name" = "checkov" ]; then
        if python3 -c "import checkov" &>/dev/null 2>&1; then
            installed=true
            path="python3 -m checkov.main"
            version=$(python3 -m checkov.main --version 2>/dev/null | head -1 || true)
        fi
    fi

    printf '{"installed":%s,"version":%s,"path":%s}' \
        "$installed" \
        "$([ -n "$version" ] && printf '"%s"' "$version" || printf 'null')" \
        "$([ -n "$path" ] && printf '"%s"' "$path" || printf 'null')"
}

# ── Detect platform ────────────────────────────────────────────────
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"

# ── Detect package managers ─────────────────────────────────────────
PMS=""
for pm in brew pip3 cargo apt-get go; do
    if command -v "$pm" &>/dev/null; then
        [ -n "$PMS" ] && PMS="${PMS},"
        PMS="${PMS}\"${pm}\""
    fi
done

# ── Check each scanner ─────────────────────────────────────────────
GITLEAKS=$(check_tool "gitleaks" "gitleaks version")
CHECKOV=$(check_tool "checkov" "checkov --version")
TRIVY=$(check_tool "trivy" "trivy --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'")
ZIZMOR=$(check_tool "zizmor" "zizmor --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'")

# ── Output JSON ─────────────────────────────────────────────────────
cat <<EOF
{"gitleaks":${GITLEAKS},"checkov":${CHECKOV},"trivy":${TRIVY},"zizmor":${ZIZMOR},"platform":"${PLATFORM}","package_managers":[${PMS}]}
EOF
```

- [ ] **Step 4: Make executable and run tests**

```bash
chmod +x scripts/doctor.sh
bash tests/run-tests.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/doctor.sh tests/test-doctor.sh
git commit -m "feat: add doctor.sh with tests"
```

---

### Task 8: doctor.md Command

**Files:**
- Create: `commands/doctor.md`

Markdown command that tells Claude to run doctor.sh and present results conversationally.

- [ ] **Step 1: Write commands/doctor.md**

```bash
mkdir -p commands
```

Write `commands/doctor.md`:
````markdown
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

3. For each missing tool, provide install commands based on the detected platform and package managers:

**gitleaks:**
- macOS: `brew install gitleaks`
- Linux: `brew install gitleaks` or download from https://github.com/gitleaks/gitleaks/releases

**checkov:**
- All platforms: `pip3 install checkov`
- macOS: `brew install checkov`

**trivy:**
- macOS: `brew install trivy`
- Linux: `sudo apt-get install trivy` or download from https://github.com/aquasecurity/trivy/releases

**zizmor:**
- All platforms: `pip3 install zizmor` or `cargo install zizmor`

4. Briefly explain what each scanner does:
- **gitleaks**: Scans for hardcoded secrets, API keys, and credentials in staged changes
- **checkov**: Checks Infrastructure-as-Code files (Dockerfiles, Terraform, k8s) for security misconfigurations
- **trivy**: Scans dependency lock files for known HIGH/CRITICAL vulnerabilities (CVEs)
- **zizmor**: Checks GitHub Actions workflows for security issues (injection risks, unpinned actions)
````

- [ ] **Step 2: Commit**

```bash
git add commands/doctor.md
git commit -m "feat: add /seatbelt doctor command"
```

---

### Task 9: README.md

**Files:**
- Create: `README.md`

User-facing documentation for the plugin.

- [ ] **Step 1: Write README.md**

Cover: what seatbelt does, quick install (from marketplace), what each scanner checks, fail modes, how to bypass/suppress, `/seatbelt doctor` command, requirements (bash, git, python3 + scanner binaries). Keep it concise — under 200 lines. Include badges placeholder.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

### Task 10: Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

```bash
bash tests/run-tests.sh
```

Expected: All tests PASS

- [ ] **Step 2: Verify plugin structure**

```bash
find . -type f -not -path './.git/*' -not -path './docs/*' -not -path './tests/*' -not -path './.claude/*' | sort
```

Expected: output includes at minimum these plugin files (other repo files may also appear):
```
./.claude-plugin/plugin.json
./commands/doctor.md
./hooks/hooks.json
./hooks/scripts/scan-checkov.sh
./hooks/scripts/scan-gitleaks.sh
./hooks/scripts/scan-trivy.sh
./hooks/scripts/scan-zizmor.sh
./LICENSE
./README.md
./scripts/doctor.sh
```

- [ ] **Step 3: Verify hooks.json is valid JSON**

```bash
python3 -c "import json; json.load(open('hooks/hooks.json'))" && echo "OK"
```

- [ ] **Step 4: Verify plugin.json is valid JSON**

```bash
python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))" && echo "OK"
```

- [ ] **Step 5: Verify doctor.sh outputs valid JSON**

```bash
bash scripts/doctor.sh | python3 -c "import sys, json; json.load(sys.stdin)" && echo "OK"
```

- [ ] **Step 6: Verify all scripts are executable**

```bash
for f in hooks/scripts/scan-*.sh scripts/doctor.sh tests/run-tests.sh; do
    [ -x "$f" ] && echo "OK: $f" || echo "FAIL: $f not executable"
done
```
