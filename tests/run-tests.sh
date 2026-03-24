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
    if ! echo "$STDOUT" | grep -qE '"decision":[[:space:]]*"block"'; then
        ERRORS="${ERRORS}\n  Expected stdout to contain block decision JSON"
        return 1
    fi
}

assert_stdout_no_block() {
    if echo "$STDOUT" | grep -qE '"decision":[[:space:]]*"block"'; then
        ERRORS="${ERRORS}\n  Expected stdout NOT to contain block decision JSON"
        return 1
    fi
}

# ── Run a single test ────────────────────────────────────────────────
# Usage: run_hook_test "test name" script_path fixture_path [env_vars...]
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
    local tmpout tmperr
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
