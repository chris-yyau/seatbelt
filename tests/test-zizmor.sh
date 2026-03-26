# Tests for scan-zizmor.sh
ZIZMOR_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-zizmor.sh"

# ── Non-commit commands should be ignored ────────────────────────────
test_zizmor_ignores_npm_install() {
    run_hook_test "zizmor ignores npm install" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "zizmor ignores npm install" || fail "zizmor ignores npm install"
}
test_zizmor_ignores_npm_install

test_zizmor_ignores_git_push() {
    run_hook_test "zizmor ignores git push" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/git-push.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "zizmor ignores git push" || fail "zizmor ignores git push"
}
test_zizmor_ignores_git_push

# ── Skip overrides ───────────────────────────────────────────────────
test_zizmor_skip_seatbelt() {
    run_hook_test "zizmor respects SKIP_SEATBELT" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "zizmor respects SKIP_SEATBELT" || fail "zizmor respects SKIP_SEATBELT"
}
test_zizmor_skip_seatbelt

test_zizmor_skip_zizmor() {
    run_hook_test "zizmor respects SKIP_ZIZMOR" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_ZIZMOR=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "zizmor respects SKIP_ZIZMOR" || fail "zizmor respects SKIP_ZIZMOR"
}
test_zizmor_skip_zizmor

# ── Degraded mode (scanner not installed) ────────────────────────────
test_zizmor_degraded_mode() {
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
        bash "$ZIZMOR_SCRIPT" <"$FIXTURES_DIR/git-commit.json" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" && rm -rf "$tmpbin"
    assert_exit_0 && assert_stdout_no_block && assert_stderr_contains "SEATBELT DEGRADED" && \
        pass "zizmor degraded mode when not installed" || fail "zizmor degraded mode when not installed"
}
test_zizmor_degraded_mode

# ── Zizmor never blocks (warn only) ─────────────────────────────────
test_zizmor_never_blocks() {
    run_hook_test "zizmor never blocks" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/git-commit.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_no_block && \
        pass "zizmor never emits block decision" || fail "zizmor never emits block decision"
}
test_zizmor_never_blocks
