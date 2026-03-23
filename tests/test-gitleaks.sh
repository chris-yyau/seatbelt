# Tests for scan-gitleaks.sh
GITLEAKS_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-gitleaks.sh"

# ── Non-commit commands should be ignored ────────────────────────────
test_gitleaks_ignores_npm_install() {
    run_hook_test "gitleaks ignores npm install" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "gitleaks ignores npm install" || fail "gitleaks ignores npm install"
}
test_gitleaks_ignores_npm_install

test_gitleaks_ignores_git_push() {
    run_hook_test "gitleaks ignores git push" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-push.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "gitleaks ignores git push" || fail "gitleaks ignores git push"
}
test_gitleaks_ignores_git_push

test_gitleaks_ignores_grep_git_commit() {
    run_hook_test "gitleaks ignores grep git commit" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/grep-git-commit.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "gitleaks ignores grep git commit" || fail "gitleaks ignores grep git commit"
}
test_gitleaks_ignores_grep_git_commit

# ── Skip overrides ───────────────────────────────────────────────────
test_gitleaks_skip_seatbelt() {
    run_hook_test "gitleaks respects SKIP_SEATBELT" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "gitleaks respects SKIP_SEATBELT" || fail "gitleaks respects SKIP_SEATBELT"
}
test_gitleaks_skip_seatbelt

test_gitleaks_skip_gitleaks() {
    run_hook_test "gitleaks respects SKIP_GITLEAKS" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_GITLEAKS=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "gitleaks respects SKIP_GITLEAKS" || fail "gitleaks respects SKIP_GITLEAKS"
}
test_gitleaks_skip_gitleaks

# ── Degraded mode (scanner not installed) ────────────────────────────
test_gitleaks_degraded_mode() {
    local tmpbin
    tmpbin=$(make_degraded_path)
    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    (
        export PATH="$tmpbin"
        cat "$FIXTURES_DIR/git-commit.json" | bash "$GITLEAKS_SCRIPT" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" && rm -rf "$tmpbin"
    assert_exit_0 && assert_stdout_no_block && assert_stderr_contains "SEATBELT DEGRADED" && \
        pass "gitleaks degraded mode when not installed" || fail "gitleaks degraded mode when not installed"
}
test_gitleaks_degraded_mode

# ── CamelCase field detection ────────────────────────────────────────
test_gitleaks_camelcase_fields() {
    local tmpbin
    tmpbin=$(make_degraded_path)
    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    (
        export PATH="$tmpbin"
        cat "$FIXTURES_DIR/git-commit-camelcase.json" | bash "$GITLEAKS_SCRIPT" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" && rm -rf "$tmpbin"
    assert_exit_0 && assert_stderr_contains "SEATBELT DEGRADED" && \
        pass "gitleaks detects camelCase fields" || fail "gitleaks detects camelCase fields"
}
test_gitleaks_camelcase_fields

# ── Env-prefixed commit detection ────────────────────────────────────
test_gitleaks_env_prefix_commit() {
    local tmpbin
    tmpbin=$(make_degraded_path)
    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    (
        export PATH="$tmpbin"
        cat "$FIXTURES_DIR/git-commit-env-prefix.json" | bash "$GITLEAKS_SCRIPT" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" && rm -rf "$tmpbin"
    assert_exit_0 && assert_stderr_contains "SEATBELT DEGRADED" && \
        pass "gitleaks detects env-prefixed commit" || fail "gitleaks detects env-prefixed commit"
}
test_gitleaks_env_prefix_commit
