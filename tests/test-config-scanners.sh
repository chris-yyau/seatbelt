# Tests for config-gated scanner skipping
GITLEAKS_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-gitleaks.sh"
CHECKOV_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-checkov.sh"
TRIVY_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-trivy.sh"
ZIZMOR_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-zizmor.sh"

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
