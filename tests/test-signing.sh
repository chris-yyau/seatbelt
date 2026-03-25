# Tests for scan-signing.sh
SIGNING_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-signing.sh"

# ── Non-commit commands should be ignored ────────────────────────────
test_signing_ignores_npm_install() {
    run_hook_test "signing ignores npm install" "$SIGNING_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "signing ignores npm install" || fail "signing ignores npm install"
}
test_signing_ignores_npm_install

test_signing_ignores_git_push() {
    run_hook_test "signing ignores git push" "$SIGNING_SCRIPT" "$FIXTURES_DIR/git-push.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "signing ignores git push" || fail "signing ignores git push"
}
test_signing_ignores_git_push

# ── Skip overrides ───────────────────────────────────────────────────
test_signing_skip_seatbelt() {
    run_hook_test "signing respects SKIP_SEATBELT" "$SIGNING_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SEATBELT=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "signing respects SKIP_SEATBELT" || fail "signing respects SKIP_SEATBELT"
}
test_signing_skip_seatbelt

test_signing_skip_signing() {
    run_hook_test "signing respects SKIP_SIGNING" "$SIGNING_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SKIP_SIGNING=1"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "signing respects SKIP_SIGNING" || fail "signing respects SKIP_SIGNING"
}
test_signing_skip_signing

# ── Config override ──────────────────────────────────────────────────
test_signing_config_disabled() {
    run_hook_test "signing respects config disabled" "$SIGNING_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_SIGNING_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "signing respects SEATBELT_SIGNING_ENABLED=false" || fail "signing respects SEATBELT_SIGNING_ENABLED=false"
}
test_signing_config_disabled

# ── Warns when gpgsign not configured ────────────────────────────────
test_signing_warns_when_not_configured() {
    # Run in a temporary git repo where commit.gpgsign is NOT set,
    # so the scanner fires the advisory warning regardless of the host config.
    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr tmprepo
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    tmprepo=$(mktemp -d)
    (
        cd "$tmprepo" && git init -q && git config commit.gpgsign false
        cat "$FIXTURES_DIR/git-commit.json" | bash "$SIGNING_SCRIPT" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" && rm -rf "$tmprepo"
    assert_exit_0 && assert_stdout_empty && assert_stderr_contains "commit signing not enabled" && \
        pass "signing warns when gpgsign not configured" || fail "signing warns when gpgsign not configured"
}
test_signing_warns_when_not_configured

# ── Silent when -S flag present ──────────────────────────────────────
test_signing_silent_with_s_flag() {
    # Run in a temp repo WITHOUT gpgsign so only -S flag prevents the warning
    local tmpfixture tmprepo
    tmpfixture=$(mktemp)
    tmprepo=$(mktemp -d)
    printf '{"tool_name":"Bash","tool_input":{"command":"git commit -S -m \"feat: signed commit\""}}' > "$tmpfixture"
    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    (
        cd "$tmprepo" && git init -q && git config commit.gpgsign false
        cat "$tmpfixture" | bash "$SIGNING_SCRIPT" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr" "$tmpfixture" && rm -rf "$tmprepo"
    # Should NOT warn because -S is present
    if [ -n "$STDERR" ] && echo "$STDERR" | grep -q "commit signing"; then
        ERRORS="\n  Expected no signing warning when -S flag present, but got: $STDERR"
        fail "signing silent when -S flag in commit command"
    else
        assert_exit_0 && assert_stdout_empty && pass "signing silent when -S flag in commit command" || fail "signing silent when -S flag in commit command"
    fi
}
test_signing_silent_with_s_flag

# ── Never blocks ──────────────────────────────────────────────────────
test_signing_never_blocks() {
    run_hook_test "signing never blocks" "$SIGNING_SCRIPT" "$FIXTURES_DIR/git-commit.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_no_block && \
        pass "signing never emits block decision" || fail "signing never emits block decision"
}
test_signing_never_blocks
