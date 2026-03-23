# Tests for scan-trivy.sh
TRIVY_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-trivy.sh"

# ── Non-commit commands should be ignored ────────────────────────────
test_trivy_ignores_npm_install() {
    run_hook_test "trivy ignores npm install" "$TRIVY_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "trivy ignores npm install" || fail "trivy ignores npm install"
}
test_trivy_ignores_npm_install

test_trivy_ignores_git_push() {
    run_hook_test "trivy ignores git push" "$TRIVY_SCRIPT" "$FIXTURES_DIR/git-push.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "trivy ignores git push" || fail "trivy ignores git push"
}
test_trivy_ignores_git_push

# ── Skip overrides ───────────────────────────────────────────────────
test_trivy_skip_seatbelt() {
    run_hook_test "trivy respects SKIP_SEATBELT" "$TRIVY_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "trivy respects SKIP_SEATBELT" || fail "trivy respects SKIP_SEATBELT"
}
test_trivy_skip_seatbelt

test_trivy_skip_trivy() {
    run_hook_test "trivy respects SKIP_TRIVY" "$TRIVY_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_TRIVY=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "trivy respects SKIP_TRIVY" || fail "trivy respects SKIP_TRIVY"
}
test_trivy_skip_trivy

# ── Degraded mode (scanner not installed) ────────────────────────────
test_trivy_degraded_mode() {
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
        cat "$FIXTURES_DIR/git-commit.json" | bash "$TRIVY_SCRIPT" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" && rm -rf "$tmpbin"
    assert_exit_0 && assert_stdout_no_block && assert_stderr_contains "SEATBELT DEGRADED" && \
        pass "trivy degraded mode when not installed" || fail "trivy degraded mode when not installed"
}
test_trivy_degraded_mode

# ── Trivy never blocks (warn only) ──────────────────────────────────
test_trivy_never_blocks() {
    run_hook_test "trivy never blocks" "$TRIVY_SCRIPT" "$FIXTURES_DIR/git-commit.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_no_block && \
        pass "trivy never emits block decision" || fail "trivy never emits block decision"
}
test_trivy_never_blocks
