# Tests for config-gated scanner skipping
GITLEAKS_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-gitleaks.sh"
CHECKOV_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-checkov.sh"
TRIVY_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-trivy.sh"
ZIZMOR_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-zizmor.sh"
SHELLCHECK_SC_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-shellcheck.sh"
COMMITLINT_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-commitlint.sh"
SIGNING_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-signing.sh"

test_gitleaks_config_disabled() {
    run_hook_test "gitleaks respects config disabled" "$GITLEAKS_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_GITLEAKS_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "gitleaks respects SEATBELT_GITLEAKS_ENABLED=false" || fail "gitleaks respects SEATBELT_GITLEAKS_ENABLED=false"
}
test_gitleaks_config_disabled

test_checkov_config_disabled() {
    run_hook_test "checkov respects config disabled" "$CHECKOV_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_CHECKOV_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "checkov respects SEATBELT_CHECKOV_ENABLED=false" || fail "checkov respects SEATBELT_CHECKOV_ENABLED=false"
}
test_checkov_config_disabled

test_trivy_config_disabled() {
    run_hook_test "trivy respects config disabled" "$TRIVY_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_TRIVY_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "trivy respects SEATBELT_TRIVY_ENABLED=false" || fail "trivy respects SEATBELT_TRIVY_ENABLED=false"
}
test_trivy_config_disabled

test_zizmor_config_disabled() {
    run_hook_test "zizmor respects config disabled" "$ZIZMOR_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_ZIZMOR_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "zizmor respects SEATBELT_ZIZMOR_ENABLED=false" || fail "zizmor respects SEATBELT_ZIZMOR_ENABLED=false"
}
test_zizmor_config_disabled

test_shellcheck_config_disabled() {
    run_hook_test "shellcheck respects config disabled" "$SHELLCHECK_SC_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_SHELLCHECK_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "shellcheck respects SEATBELT_SHELLCHECK_ENABLED=false" || fail "shellcheck respects SEATBELT_SHELLCHECK_ENABLED=false"
}
test_shellcheck_config_disabled

test_commitlint_config_disabled_scanner() {
    run_hook_test "commitlint respects config disabled" "$COMMITLINT_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_COMMITLINT_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "commitlint respects SEATBELT_COMMITLINT_ENABLED=false (config-scanners)" || fail "commitlint respects SEATBELT_COMMITLINT_ENABLED=false (config-scanners)"
}
test_commitlint_config_disabled_scanner

test_signing_config_disabled_scanner() {
    run_hook_test "signing respects config disabled" "$SIGNING_SCRIPT" "$FIXTURES_DIR/git-commit.json" "SEATBELT_SIGNING_ENABLED=false"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && pass "signing respects SEATBELT_SIGNING_ENABLED=false (config-scanners)" || fail "signing respects SEATBELT_SIGNING_ENABLED=false (config-scanners)"
}
test_signing_config_disabled_scanner
