# Tests for lib/detect-commit.sh
DETECT_LIB="$PROJECT_ROOT/hooks/scripts/lib/detect-commit.sh"

# Helper: run the lib with given fixture, capture IS_GIT_COMMIT
run_detect() {
    local fixture="$1"
    shift
    local result
    result=$(
        for var in "$@"; do export "$var"; done
        HOOK_DATA=$(cat "$fixture")
        export HOOK_DATA
        source "$DETECT_LIB"
        echo "$IS_GIT_COMMIT"
    )
    echo "$result"
}

# ── Detects git commit ─────────────────────────────────────────
test_detect_git_commit() {
    ERRORS=""
    local result
    result=$(run_detect "$FIXTURES_DIR/git-commit.json")
    if [ "$result" = "yes" ]; then
        pass "detect-commit: identifies git commit"
    else
        ERRORS="\n  Expected 'yes', got '$result'"
        fail "detect-commit: identifies git commit"
    fi
}
test_detect_git_commit

# ── Ignores npm install ────────────────────────────────────────
test_detect_ignores_npm() {
    ERRORS=""
    local result
    result=$(run_detect "$FIXTURES_DIR/npm-install.json")
    if [ -z "$result" ]; then
        pass "detect-commit: ignores npm install"
    else
        ERRORS="\n  Expected empty, got '$result'"
        fail "detect-commit: ignores npm install"
    fi
}
test_detect_ignores_npm

# ── Ignores git push ──────────────────────────────────────────
test_detect_ignores_push() {
    ERRORS=""
    local result
    result=$(run_detect "$FIXTURES_DIR/git-push.json")
    if [ -z "$result" ]; then
        pass "detect-commit: ignores git push"
    else
        ERRORS="\n  Expected empty, got '$result'"
        fail "detect-commit: ignores git push"
    fi
}
test_detect_ignores_push

# ── Detects chained command with git commit ───────────────────
test_detect_chained_commit() {
    ERRORS=""
    local result
    result=$(run_detect "$FIXTURES_DIR/git-commit-chained.json")
    if [ "$result" = "yes" ]; then
        pass "detect-commit: identifies chained git commit"
    else
        ERRORS="\n  Expected 'yes', got '$result'"
        fail "detect-commit: identifies chained git commit"
    fi
}
test_detect_chained_commit

# ── Detects env-prefixed commit ───────────────────────────────
test_detect_env_prefix() {
    ERRORS=""
    local result
    result=$(run_detect "$FIXTURES_DIR/git-commit-env-prefix.json")
    if [ "$result" = "yes" ]; then
        pass "detect-commit: identifies env-prefixed commit"
    else
        ERRORS="\n  Expected 'yes', got '$result'"
        fail "detect-commit: identifies env-prefixed commit"
    fi
}
test_detect_env_prefix

# ── Detects camelCase field names ─────────────────────────────
test_detect_camelcase() {
    ERRORS=""
    local result
    result=$(run_detect "$FIXTURES_DIR/git-commit-camelcase.json")
    if [ "$result" = "yes" ]; then
        pass "detect-commit: identifies camelCase fields"
    else
        ERRORS="\n  Expected 'yes', got '$result'"
        fail "detect-commit: identifies camelCase fields"
    fi
}
test_detect_camelcase

# ── Detects amend commit ──────────────────────────────────────
test_detect_amend() {
    ERRORS=""
    local result
    result=$(run_detect "$FIXTURES_DIR/git-commit-amend.json")
    if [ "$result" = "yes" ]; then
        pass "detect-commit: identifies amend commit"
    else
        ERRORS="\n  Expected 'yes', got '$result'"
        fail "detect-commit: identifies amend commit"
    fi
}
test_detect_amend

# ── Detects quoted-env-prefixed commit ────────────────────────
test_detect_quoted_env() {
    ERRORS=""
    local result
    result=$(run_detect "$FIXTURES_DIR/git-commit-quoted-env.json")
    if [ "$result" = "yes" ]; then
        pass "detect-commit: identifies quoted-env commit"
    else
        ERRORS="\n  Expected 'yes', got '$result'"
        fail "detect-commit: identifies quoted-env commit"
    fi
}
test_detect_quoted_env

# ── Ignores grep containing 'git commit' ─────────────────────
test_detect_ignores_grep() {
    ERRORS=""
    local result
    result=$(run_detect "$FIXTURES_DIR/grep-git-commit.json")
    if [ -z "$result" ]; then
        pass "detect-commit: ignores grep git commit"
    else
        ERRORS="\n  Expected empty, got '$result'"
        fail "detect-commit: ignores grep git commit"
    fi
}
test_detect_ignores_grep

# ── Falls back to empty on missing python3 ───────────────────
test_detect_no_python3() {
    ERRORS=""
    local tmpbin
    tmpbin=$(make_degraded_path)
    # Remove python3 from the temp PATH
    rm -f "$tmpbin/python3"
    local result
    result=$(
        export PATH="$tmpbin"
        HOOK_DATA=$(cat "$FIXTURES_DIR/git-commit.json")
        export HOOK_DATA
        source "$DETECT_LIB"
        echo "$IS_GIT_COMMIT"
    )
    rm -rf "$tmpbin"
    if [ -z "$result" ]; then
        pass "detect-commit: empty without python3 (fail-open)"
    else
        ERRORS="\n  Expected empty, got '$result'"
        fail "detect-commit: empty without python3 (fail-open)"
    fi
}
test_detect_no_python3
