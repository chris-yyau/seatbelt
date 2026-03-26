# Tests for scan-semgrep.sh
SEMGREP_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-semgrep.sh"

# ── Non-commit commands should be ignored ────────────────────────────
test_semgrep_ignores_npm_install() {
    run_hook_test "semgrep ignores npm install" "$SEMGREP_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "semgrep ignores npm install" || fail "semgrep ignores npm install"
}
test_semgrep_ignores_npm_install

test_semgrep_ignores_git_push() {
    run_hook_test "semgrep ignores git push" "$SEMGREP_SCRIPT" "$FIXTURES_DIR/git-push.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "semgrep ignores git push" || fail "semgrep ignores git push"
}
test_semgrep_ignores_git_push

# ── Skip overrides ───────────────────────────────────────────────────
test_semgrep_skip_seatbelt() {
    run_hook_test "semgrep respects SKIP_SEATBELT" "$SEMGREP_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "semgrep respects SKIP_SEATBELT" || fail "semgrep respects SKIP_SEATBELT"
}
test_semgrep_skip_seatbelt

test_semgrep_skip_semgrep() {
    run_hook_test "semgrep respects SKIP_SEMGREP" "$SEMGREP_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEMGREP=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "semgrep respects SKIP_SEMGREP" || fail "semgrep respects SKIP_SEMGREP"
}
test_semgrep_skip_semgrep

# ── Config override ──────────────────────────────────────────────────
test_semgrep_config_disabled() {
    run_hook_test "semgrep respects config disabled" "$SEMGREP_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_SEMGREP_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "semgrep respects SEATBELT_SEMGREP_ENABLED=false" || fail "semgrep respects SEATBELT_SEMGREP_ENABLED=false"
}
test_semgrep_config_disabled

# ── Degraded mode (scanner not installed) ────────────────────────────
test_semgrep_degraded_mode() {
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
        bash "$SEMGREP_SCRIPT" <"$FIXTURES_DIR/git-commit.json" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" && rm -rf "$tmpbin"
    assert_exit_0 && assert_stdout_no_block && assert_stderr_contains "SEATBELT DEGRADED" && \
        pass "semgrep degraded mode when not installed" || fail "semgrep degraded mode when not installed"
}
test_semgrep_degraded_mode

# ── Semgrep never blocks (warn only) ──────────────────────────────────
test_semgrep_never_blocks() {
    run_hook_test "semgrep never blocks" "$SEMGREP_SCRIPT" "$FIXTURES_DIR/git-commit.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_no_block && \
        pass "semgrep never emits block decision" || fail "semgrep never emits block decision"
}
test_semgrep_never_blocks

# ── Clean exit on commit with no source files ─────────────────────────
test_semgrep_no_source_files() {
    run_hook_test "semgrep clean exit no source files" "$SEMGREP_SCRIPT" "$FIXTURES_DIR/git-commit.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && \
        pass "semgrep clean exit when no source files staged" || fail "semgrep clean exit when no source files staged"
}
test_semgrep_no_source_files
