# Tests for scan-checkov.sh
CHECKOV_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-checkov.sh"

# ── Non-commit commands should be ignored ────────────────────────────
test_checkov_ignores_npm_install() {
    run_hook_test "checkov ignores npm install" "$CHECKOV_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "checkov ignores npm install" || fail "checkov ignores npm install"
}
test_checkov_ignores_npm_install

test_checkov_ignores_git_push() {
    run_hook_test "checkov ignores git push" "$CHECKOV_SCRIPT" "$FIXTURES_DIR/git-push.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "checkov ignores git push" || fail "checkov ignores git push"
}
test_checkov_ignores_git_push

# ── Skip overrides ───────────────────────────────────────────────────
test_checkov_skip_seatbelt() {
    run_hook_test "checkov respects SKIP_SEATBELT" "$CHECKOV_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "checkov respects SKIP_SEATBELT" || fail "checkov respects SKIP_SEATBELT"
}
test_checkov_skip_seatbelt

test_checkov_skip_checkov() {
    run_hook_test "checkov respects SKIP_CHECKOV" "$CHECKOV_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_CHECKOV=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "checkov respects SKIP_CHECKOV" || fail "checkov respects SKIP_CHECKOV"
}
test_checkov_skip_checkov

# ── Degraded mode (scanner not installed) ────────────────────────────
test_checkov_degraded_mode() {
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
        bash "$CHECKOV_SCRIPT" <"$FIXTURES_DIR/git-commit.json" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" && rm -rf "$tmpbin"
    assert_exit_0 && assert_stdout_no_block && assert_stderr_contains "SEATBELT DEGRADED" && \
        pass "checkov degraded mode when not installed" || fail "checkov degraded mode when not installed"
}
test_checkov_degraded_mode

# ── Chained command detection ────────────────────────────────────────
test_checkov_detects_chained_commit() {
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
        bash "$CHECKOV_SCRIPT" <"$FIXTURES_DIR/git-commit-chained.json" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" && rm -rf "$tmpbin"
    assert_exit_0 && assert_stderr_contains "SEATBELT DEGRADED" && \
        pass "checkov detects chained commit" || fail "checkov detects chained commit"
}
test_checkov_detects_chained_commit
