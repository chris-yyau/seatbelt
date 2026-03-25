# Tests for scan-shellcheck.sh
SHELLCHECK_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-shellcheck.sh"

# ── Non-commit commands should be ignored ────────────────────────────
test_shellcheck_ignores_npm_install() {
    run_hook_test "shellcheck ignores npm install" "$SHELLCHECK_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "shellcheck ignores npm install" || fail "shellcheck ignores npm install"
}
test_shellcheck_ignores_npm_install

test_shellcheck_ignores_git_push() {
    run_hook_test "shellcheck ignores git push" "$SHELLCHECK_SCRIPT" "$FIXTURES_DIR/git-push.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "shellcheck ignores git push" || fail "shellcheck ignores git push"
}
test_shellcheck_ignores_git_push

# ── Skip overrides ───────────────────────────────────────────────────
test_shellcheck_skip_seatbelt() {
    run_hook_test "shellcheck respects SKIP_SEATBELT" "$SHELLCHECK_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "shellcheck respects SKIP_SEATBELT" || fail "shellcheck respects SKIP_SEATBELT"
}
test_shellcheck_skip_seatbelt

test_shellcheck_skip_shellcheck() {
    run_hook_test "shellcheck respects SKIP_SHELLCHECK" "$SHELLCHECK_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SHELLCHECK=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "shellcheck respects SKIP_SHELLCHECK" || fail "shellcheck respects SKIP_SHELLCHECK"
}
test_shellcheck_skip_shellcheck

# ── Config file override ────────────────────────────────────────────
test_shellcheck_config_disabled() {
    run_hook_test "shellcheck respects SEATBELT_SHELLCHECK_ENABLED=false" "$SHELLCHECK_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_SHELLCHECK_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "shellcheck respects SEATBELT_SHELLCHECK_ENABLED=false" || fail "shellcheck respects SEATBELT_SHELLCHECK_ENABLED=false"
}
test_shellcheck_config_disabled

# ── Degraded mode (scanner not installed) ────────────────────────────
test_shellcheck_degraded_mode() {
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
        cat "$FIXTURES_DIR/git-commit.json" | bash "$SHELLCHECK_SCRIPT" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" && rm -rf "$tmpbin"
    assert_exit_0 && assert_stdout_no_block && assert_stderr_contains "SEATBELT DEGRADED" && \
        pass "shellcheck degraded mode when not installed" || fail "shellcheck degraded mode when not installed"
}
test_shellcheck_degraded_mode

# ── Shellcheck never blocks (warn only) ──────────────────────────────
test_shellcheck_never_blocks() {
    run_hook_test "shellcheck never blocks" "$SHELLCHECK_SCRIPT" "$FIXTURES_DIR/git-commit.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_no_block && \
        pass "shellcheck never emits block decision" || fail "shellcheck never emits block decision"
}
test_shellcheck_never_blocks

# ── Clean exit when no .sh files staged ──────────────────────────────
test_shellcheck_clean_no_sh_files() {
    run_hook_test "shellcheck clean exit with no .sh files" "$SHELLCHECK_SCRIPT" "$FIXTURES_DIR/git-commit.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && \
        pass "shellcheck clean exit when no .sh files staged" || fail "shellcheck clean exit when no .sh files staged"
}
test_shellcheck_clean_no_sh_files

# ── Never emits block decision ───────────────────────────────────────
test_shellcheck_no_block_emit() {
    run_hook_test "shellcheck no block emit" "$SHELLCHECK_SCRIPT" "$FIXTURES_DIR/git-commit.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_no_block && \
        pass "shellcheck never emits block decision (explicit)" || fail "shellcheck never emits block decision (explicit)"
}
test_shellcheck_no_block_emit
