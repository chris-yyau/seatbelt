# Tests for scan-summary.sh (PostToolUse aggregate summary)
SUMMARY_SCRIPT="$PROJECT_ROOT/hooks/scripts/scan-summary.sh"

# ── Summary ignores non-commit commands ───────────────────────
test_summary_ignores_npm() {
    run_hook_test "summary ignores npm" "$SUMMARY_SCRIPT" "$FIXTURES_DIR/npm-install.json"
    ERRORS=""
    assert_exit_0 && assert_stdout_empty && \
        pass "summary: ignores non-commit commands" || fail "summary: ignores non-commit commands"
}
test_summary_ignores_npm

# ── Summary with no result files → no output ─────────────────
test_summary_no_results() {
    local tmpdir
    tmpdir=$(mktemp -d)
    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    (
        export SEATBELT_RESULT_DIR="$tmpdir/seatbelt-nonexistent"
        bash "$SUMMARY_SCRIPT" <"$FIXTURES_DIR/git-commit.json" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr"
    rm -rf "$tmpdir"
    assert_exit_0 && assert_stdout_empty
    if echo "$STDERR" | grep -qF "SEATBELT SUMMARY"; then
        ERRORS="\n  Should not emit summary when no results"
        fail "summary: no results → no output"
    else
        pass "summary: no results → no output"
    fi
}
test_summary_no_results

# ── Summary with result files → emits aggregated count ───────
test_summary_aggregates_results() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local resultdir="$tmpdir/seatbelt-results"
    mkdir -p "$resultdir"
    echo "2 vulnerabilities in package-lock.json" > "$resultdir/trivy"
    echo "1 issue in ci.yml" > "$resultdir/zizmor"

    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    (
        export SEATBELT_RESULT_DIR="$resultdir"
        bash "$SUMMARY_SCRIPT" <"$FIXTURES_DIR/git-commit.json" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr"
    rm -rf "$tmpdir"

    assert_exit_0
    if echo "$STDERR" | grep -qF "SEATBELT SUMMARY"; then
        pass "summary: aggregates results from multiple scanners"
    else
        ERRORS="\n  Expected stderr to contain 'SEATBELT SUMMARY'"
        fail "summary: aggregates results from multiple scanners"
    fi
}
test_summary_aggregates_results

# ── Summary cleans up result dir ─────────────────────────────
test_summary_cleans_up() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local resultdir="$tmpdir/seatbelt-results"
    mkdir -p "$resultdir"
    echo "1 issue in ci.yml" > "$resultdir/zizmor"

    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    (
        export SEATBELT_RESULT_DIR="$resultdir"
        bash "$SUMMARY_SCRIPT" <"$FIXTURES_DIR/git-commit.json" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr"

    if [ -d "$resultdir" ]; then
        ERRORS="\n  Result dir should be cleaned up after summary"
        fail "summary: cleans up result dir"
    else
        pass "summary: cleans up result dir"
    fi
    rm -rf "$tmpdir"
}
test_summary_cleans_up

# ── Summary sums multi-line result files (multiple scanned files) ──
test_summary_multi_file_scanner() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local resultdir="$tmpdir/seatbelt-results"
    mkdir -p "$resultdir"
    # Simulate trivy finding vulns in two different lockfiles (appended lines)
    printf '3 vulnerabilities in package-lock.json\n2 vulnerabilities in yarn.lock\n' > "$resultdir/trivy"
    echo "1 issue in ci.yml" > "$resultdir/zizmor"

    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    (
        export SEATBELT_RESULT_DIR="$resultdir"
        bash "$SUMMARY_SCRIPT" <"$FIXTURES_DIR/git-commit.json" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr"
    rm -rf "$tmpdir"

    assert_exit_0
    if echo "$STDERR" | grep -qF "6 finding(s) from 2 scanner(s)"; then
        pass "summary: sums multi-line result files correctly"
    else
        ERRORS="\n  Expected '6 finding(s) from 2 scanner(s)', got: $STDERR"
        fail "summary: sums multi-line result files correctly"
    fi
}
test_summary_multi_file_scanner

# ── Summary handles non-numeric lines gracefully ─────────────
test_summary_non_numeric_lines() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local resultdir="$tmpdir/seatbelt-results"
    mkdir -p "$resultdir"
    # Simulate a result file with a non-numeric prefix (e.g. corrupted data)
    printf 'unexpected line with no number\n2 vulnerabilities in package-lock.json\n' > "$resultdir/trivy"

    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0
    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)
    (
        export SEATBELT_RESULT_DIR="$resultdir"
        bash "$SUMMARY_SCRIPT" <"$FIXTURES_DIR/git-commit.json" >"$tmpout" 2>"$tmperr"
    ) || EXIT_CODE=$?
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr"
    rm -rf "$tmpdir"

    assert_exit_0
    if echo "$STDERR" | grep -qF "2 finding(s) from 1 scanner(s)"; then
        pass "summary: handles non-numeric lines gracefully"
    else
        ERRORS="\n  Expected '2 finding(s) from 1 scanner(s)', got: $STDERR"
        fail "summary: handles non-numeric lines gracefully"
    fi
}
test_summary_non_numeric_lines
