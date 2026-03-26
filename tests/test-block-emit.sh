# Tests for lib/block-emit.sh
BLOCK_EMIT_SCRIPT="$PROJECT_ROOT/hooks/scripts/lib/block-emit.sh"

# ── block_emit outputs valid JSON block decision ──────────────────
test_block_emit_json_output() {
    local output
    output=$(SEATBELT_STRICT=true source "$BLOCK_EMIT_SCRIPT" && block_emit "test-scanner" "secret found")
    ERRORS=""
    if echo "$output" | grep -qE '"decision":\s*"block"'; then
        pass "block_emit: outputs block decision JSON"
    else
        ERRORS="\n  Expected block JSON, got: $output"
        fail "block_emit: outputs block decision JSON"
    fi
}
test_block_emit_json_output

# ── block_emit with strict=false suppresses block to warning ──────
test_block_emit_strict_false() {
    local tmpout tmperr output stderr_out
    tmpout=$(mktemp); tmperr=$(mktemp)
    (export SEATBELT_STRICT=false && source "$BLOCK_EMIT_SCRIPT" && block_emit "test-scanner" "secret found") >"$tmpout" 2>"$tmperr"
    output=$(cat "$tmpout"); stderr_out=$(cat "$tmperr")
    rm -f "$tmpout" "$tmperr"

    ERRORS=""
    if [ -z "$output" ] || ! echo "$output" | grep -qE '"decision"'; then
        if echo "$stderr_out" | grep -qF "test-scanner would block"; then
            pass "block_emit: strict=false suppresses block to stderr warning"
        else
            ERRORS="\n  Expected stderr warning about suppressed block, got stderr: $stderr_out"
            fail "block_emit: strict=false suppresses block to stderr warning"
        fi
    else
        ERRORS="\n  Expected no block JSON on stdout when strict=false, got: $output"
        fail "block_emit: strict=false suppresses block to stderr warning"
    fi
}
test_block_emit_strict_false

# ── block_emit with strict=true (default) emits block ────────────
test_block_emit_strict_true_default() {
    local output
    output=$(unset SEATBELT_STRICT && source "$BLOCK_EMIT_SCRIPT" && block_emit "gitleaks" "reason")
    ERRORS=""
    if echo "$output" | grep -qE '"decision":\s*"block"'; then
        pass "block_emit: strict=true (default) emits block"
    else
        ERRORS="\n  Expected block JSON, got: $output"
        fail "block_emit: strict=true (default) emits block"
    fi
}
test_block_emit_strict_true_default

# ── block_emit escapes special characters in reason ──────────────
test_block_emit_escapes_special_chars() {
    local output
    output=$(source "$BLOCK_EMIT_SCRIPT" && block_emit "test" 'reason with "quotes" and \backslash')
    ERRORS=""
    if printf '%s' "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "block_emit: escapes special characters (valid JSON)"
    else
        ERRORS="\n  Output is not valid JSON: $output"
        fail "block_emit: escapes special characters (valid JSON)"
    fi
}
test_block_emit_escapes_special_chars

# ── block_emit strict=false does NOT write result file ───────────
test_block_emit_strict_false_no_result_file() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (SEATBELT_STRICT=false SEATBELT_RESULT_DIR="$tmpdir/results" source "$BLOCK_EMIT_SCRIPT" && block_emit "gitleaks" "secret found") >/dev/null 2>/dev/null
    ERRORS=""
    if [ ! -f "$tmpdir/results/gitleaks" ]; then
        pass "block_emit: strict=false does not write result file (scanner owns it)"
    else
        ERRORS="\n  block_emit should NOT write result files — scanners own their entries"
        fail "block_emit: strict=false does not write result file (scanner owns it)"
    fi
    rm -rf "$tmpdir"
}
test_block_emit_strict_false_no_result_file

# ── severity_at_or_above: basic comparisons ──────────────────────
test_severity_at_or_above_basic() {
    local result
    result=$(source "$BLOCK_EMIT_SCRIPT" && _seatbelt_severity_at_or_above "CRITICAL" "CRITICAL" "HIGH,CRITICAL" && echo "YES" || echo "NO")
    ERRORS=""
    if [ "$result" = "YES" ]; then
        pass "severity_at_or_above: CRITICAL >= CRITICAL"
    else
        ERRORS="\n  Expected YES, got: $result"
        fail "severity_at_or_above: CRITICAL >= CRITICAL"
    fi
}
test_severity_at_or_above_basic

test_severity_below_threshold() {
    local result
    result=$(source "$BLOCK_EMIT_SCRIPT" && _seatbelt_severity_at_or_above "HIGH" "CRITICAL" "HIGH,CRITICAL" && echo "YES" || echo "NO")
    ERRORS=""
    if [ "$result" = "NO" ]; then
        pass "severity_at_or_above: HIGH < CRITICAL"
    else
        ERRORS="\n  Expected NO, got: $result"
        fail "severity_at_or_above: HIGH < CRITICAL"
    fi
}
test_severity_below_threshold

test_severity_case_insensitive() {
    local result
    result=$(source "$BLOCK_EMIT_SCRIPT" && _seatbelt_severity_at_or_above "critical" "CRITICAL" "HIGH,CRITICAL" && echo "YES" || echo "NO")
    ERRORS=""
    if [ "$result" = "YES" ]; then
        pass "severity_at_or_above: case-insensitive"
    else
        ERRORS="\n  Expected YES, got: $result"
        fail "severity_at_or_above: case-insensitive"
    fi
}
test_severity_case_insensitive

# ── validate_severity: valid and invalid ─────────────────────────
test_validate_severity_valid() {
    local tmperr stderr_out
    tmperr=$(mktemp)
    (source "$BLOCK_EMIT_SCRIPT" && _seatbelt_validate_severity "trivy" "CRITICAL" "HIGH,CRITICAL") 2>"$tmperr"
    local exit_code=$?
    stderr_out=$(cat "$tmperr"); rm -f "$tmperr"
    ERRORS=""
    if [ "$exit_code" -eq 0 ]; then
        pass "validate_severity: CRITICAL is valid for trivy"
    else
        ERRORS="\n  Expected exit 0, got $exit_code"
        fail "validate_severity: CRITICAL is valid for trivy"
    fi
}
test_validate_severity_valid

test_validate_severity_invalid() {
    local tmperr stderr_out
    tmperr=$(mktemp)
    # _seatbelt_validate_severity returns 1 for invalid — capture stderr, ignore exit
    (source "$BLOCK_EMIT_SCRIPT" && _seatbelt_validate_severity "trivy" "MEDIUM" "HIGH,CRITICAL") 2>"$tmperr" && local was_valid=yes || local was_valid=no
    stderr_out=$(cat "$tmperr"); rm -f "$tmperr"
    ERRORS=""
    if [ "$was_valid" = "no" ] && echo "$stderr_out" | grep -qF "unknown severity"; then
        pass "validate_severity: MEDIUM is invalid for trivy, emits warning"
    else
        ERRORS="\n  Expected invalid + warning, got valid=$was_valid stderr=$stderr_out"
        fail "validate_severity: MEDIUM is invalid for trivy, emits warning"
    fi
}
test_validate_severity_invalid

test_validate_severity_empty() {
    (source "$BLOCK_EMIT_SCRIPT" && _seatbelt_validate_severity "trivy" "" "HIGH,CRITICAL")
    local exit_code=$?
    ERRORS=""
    if [ "$exit_code" -eq 0 ]; then
        pass "validate_severity: empty string is valid (no-op)"
    else
        ERRORS="\n  Expected exit 0 for empty, got $exit_code"
        fail "validate_severity: empty string is valid (no-op)"
    fi
}
test_validate_severity_empty
