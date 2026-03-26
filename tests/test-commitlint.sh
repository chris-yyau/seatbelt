# Tests for scan-commitlint.sh
COMMITLINT_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-commitlint.sh"

# ── Non-commit commands should be ignored ────────────────────────────
test_commitlint_ignores_npm_install() {
    run_hook_test "commitlint ignores npm install" "$COMMITLINT_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "commitlint ignores npm install" || fail "commitlint ignores npm install"
}
test_commitlint_ignores_npm_install

test_commitlint_ignores_git_push() {
    run_hook_test "commitlint ignores git push" "$COMMITLINT_SCRIPT" "$FIXTURES_DIR/git-push.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "commitlint ignores git push" || fail "commitlint ignores git push"
}
test_commitlint_ignores_git_push

# ── Skip overrides ───────────────────────────────────────────────────
test_commitlint_skip_seatbelt() {
    run_hook_test "commitlint respects SKIP_SEATBELT" "$COMMITLINT_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "commitlint respects SKIP_SEATBELT" || fail "commitlint respects SKIP_SEATBELT"
}
test_commitlint_skip_seatbelt

test_commitlint_skip_commitlint() {
    run_hook_test "commitlint respects SKIP_COMMITLINT" "$COMMITLINT_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_COMMITLINT=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "commitlint respects SKIP_COMMITLINT" || fail "commitlint respects SKIP_COMMITLINT"
}
test_commitlint_skip_commitlint

# ── Config override ──────────────────────────────────────────────────
test_commitlint_config_disabled() {
    run_hook_test "commitlint respects config disabled" "$COMMITLINT_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_COMMITLINT_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "commitlint respects SEATBELT_COMMITLINT_ENABLED=false" || fail "commitlint respects SEATBELT_COMMITLINT_ENABLED=false"
}
test_commitlint_config_disabled

# ── Valid conventional commit passes silently ─────────────────────────
test_commitlint_valid_message() {
    local tmpfixture
    tmpfixture=$(mktemp)
    # Use printf '%s' to prevent backslash interpretation in format string
    printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add new feature\""}}' > "$tmpfixture"
    run_hook_test "commitlint valid message" "$COMMITLINT_SCRIPT" "$tmpfixture"
    rm -f "$tmpfixture"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "commitlint valid conventional commit passes silently" || fail "commitlint valid conventional commit passes silently"
}
test_commitlint_valid_message

# ── Invalid commit message warns on stderr ────────────────────────────
test_commitlint_invalid_message() {
    local tmpfixture
    tmpfixture=$(mktemp)
    printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"added some stuff\""}}' > "$tmpfixture"

    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    (cat "$tmpfixture" | bash "$COMMITLINT_SCRIPT" >"$tmpout" 2>"$tmperr") || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" "$tmpfixture"

    assert_exit_0 && assert_stdout_empty && assert_stderr_contains "conventional commits" && \
        pass "commitlint invalid message warns on stderr" || fail "commitlint invalid message warns on stderr"
}
test_commitlint_invalid_message

# ── Handles --message long form ──────────────────────────────────────
test_commitlint_long_form_message() {
    local tmpfixture
    tmpfixture=$(mktemp)
    printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit --message \"fix: resolve bug\""}}' > "$tmpfixture"
    run_hook_test "commitlint --message form" "$COMMITLINT_SCRIPT" "$tmpfixture"
    rm -f "$tmpfixture"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "commitlint handles --message long form" || fail "commitlint handles --message long form"
}
test_commitlint_long_form_message

# ── Skips when no -m flag (interactive/amend) ────────────────────────
test_commitlint_no_message_flag() {
    local tmpfixture
    tmpfixture=$(mktemp)
    printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit --amend"}}' > "$tmpfixture"
    run_hook_test "commitlint no -m flag" "$COMMITLINT_SCRIPT" "$tmpfixture"
    rm -f "$tmpfixture"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "commitlint skips when no -m flag" || fail "commitlint skips when no -m flag"
}
test_commitlint_no_message_flag

# ── Never blocks ──────────────────────────────────────────────────────
test_commitlint_never_blocks() {
    local tmpfixture
    tmpfixture=$(mktemp)
    printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"bad message\""}}' > "$tmpfixture"
    run_hook_test "commitlint never blocks" "$COMMITLINT_SCRIPT" "$tmpfixture"
    rm -f "$tmpfixture"
    ERRORS=""
    assert_exit_0 && assert_stdout_no_block && \
        pass "commitlint never emits block decision" || fail "commitlint never emits block decision"
}
test_commitlint_never_blocks
