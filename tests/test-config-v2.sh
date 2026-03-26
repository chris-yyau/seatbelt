# Tests for lib/config.sh v6 fields (strict, severity, ruleset, timeout)
CONFIG_SCRIPT="$PROJECT_ROOT/hooks/scripts/lib/config.sh"

# Helper: unset all seatbelt vars to isolate tests
_unset_all_seatbelt_vars() {
    unset SEATBELT_GITLEAKS_ENABLED SEATBELT_CHECKOV_ENABLED SEATBELT_TRIVY_ENABLED \
          SEATBELT_ZIZMOR_ENABLED SEATBELT_SEMGREP_ENABLED SEATBELT_SHELLCHECK_ENABLED \
          SEATBELT_COMMITLINT_ENABLED SEATBELT_SIGNING_ENABLED \
          SEATBELT_STRICT SEATBELT_TRIVY_SEVERITY SEATBELT_SEMGREP_SEVERITY \
          SEATBELT_ZIZMOR_SEVERITY SEATBELT_SEMGREP_RULESET \
          SEATBELT_TRIVY_TIMEOUT SEATBELT_SEMGREP_TIMEOUT SEATBELT_SHELLCHECK_TIMEOUT \
          SEATBELT_CHECKOV_TIMEOUT SEATBELT_GITLEAKS_TIMEOUT SEATBELT_ZIZMOR_TIMEOUT \
          SEATBELT_COMMITLINT_TIMEOUT SEATBELT_SIGNING_TIMEOUT \
          2>/dev/null || true
}

# ── No config file -> strict=true, severity empty, default ruleset ──
test_config_v2_defaults() {
    local tmpdir
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q

    local result
    result=$(cd "$tmpdir" && _unset_all_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && \
        printf 'STRICT=%s\nTRIVY_SEV=%s\nSEMGREP_SEV=%s\nZIZMOR_SEV=%s\nRULESET=%s\n' \
        "$SEATBELT_STRICT" "$SEATBELT_TRIVY_SEVERITY" "$SEATBELT_SEMGREP_SEVERITY" "$SEATBELT_ZIZMOR_SEVERITY" "$SEATBELT_SEMGREP_RULESET")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "^STRICT=true$" && \
       echo "$result" | grep -q "^TRIVY_SEV=$" && \
       echo "$result" | grep -q "^SEMGREP_SEV=$" && \
       echo "$result" | grep -q "^ZIZMOR_SEV=$" && \
       echo "$result" | grep -q "^RULESET=p/security-audit$"; then
        pass "config v2: defaults — strict=true, severity empty, default ruleset"
    else
        ERRORS="\n  Got: $result"
        fail "config v2: defaults — strict=true, severity empty, default ruleset"
    fi
}
test_config_v2_defaults

# ── Strict false from config ─────────────────────────────────────
test_config_v2_strict_false() {
    local tmpdir
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-strict-false.yml" "$tmpdir/.seatbelt.yml"

    local result
    result=$(cd "$tmpdir" && _unset_all_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && printf 'STRICT=%s\n' "$SEATBELT_STRICT")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "^STRICT=false$"; then
        pass "config v2: strict=false from config file"
    else
        ERRORS="\n  Expected STRICT=false, got: $result"
        fail "config v2: strict=false from config file"
    fi
}
test_config_v2_strict_false

# ── Severity values parsed from config ───────────────────────────
test_config_v2_severity_parsed() {
    local tmpdir
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-severity.yml" "$tmpdir/.seatbelt.yml"

    local result
    result=$(cd "$tmpdir" && _unset_all_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && \
        printf 'TRIVY_SEV=%s\nSEMGREP_SEV=%s\nZIZMOR_SEV=%s\n' \
        "$SEATBELT_TRIVY_SEVERITY" "$SEATBELT_SEMGREP_SEVERITY" "$SEATBELT_ZIZMOR_SEVERITY")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "^TRIVY_SEV=CRITICAL$" && \
       echo "$result" | grep -q "^SEMGREP_SEV=error$" && \
       echo "$result" | grep -q "^ZIZMOR_SEV=high$"; then
        pass "config v2: severity values parsed from config"
    else
        ERRORS="\n  Got: $result"
        fail "config v2: severity values parsed from config"
    fi
}
test_config_v2_severity_parsed

# ── Custom ruleset parsed from config ────────────────────────────
test_config_v2_custom_ruleset() {
    local tmpdir
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-custom-ruleset.yml" "$tmpdir/.seatbelt.yml"

    local result
    result=$(cd "$tmpdir" && _unset_all_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && printf 'RULESET=%s\n' "$SEATBELT_SEMGREP_RULESET")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "^RULESET=p/owasp-top-ten$"; then
        pass "config v2: custom semgrep ruleset from config"
    else
        ERRORS="\n  Expected RULESET=p/owasp-top-ten, got: $result"
        fail "config v2: custom semgrep ruleset from config"
    fi
}
test_config_v2_custom_ruleset

# ── Timeout values parsed from config ────────────────────────────
test_config_v2_timeouts() {
    local tmpdir
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-timeouts.yml" "$tmpdir/.seatbelt.yml"

    local result
    result=$(cd "$tmpdir" && _unset_all_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && \
        printf 'TRIVY_T=%s\nSEMGREP_T=%s\nSHELLCHECK_T=%s\nCHECKOV_T=%s\n' \
        "$SEATBELT_TRIVY_TIMEOUT" "$SEATBELT_SEMGREP_TIMEOUT" "$SEATBELT_SHELLCHECK_TIMEOUT" "$SEATBELT_CHECKOV_TIMEOUT")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "^TRIVY_T=45$" && \
       echo "$result" | grep -q "^SEMGREP_T=90$" && \
       echo "$result" | grep -q "^SHELLCHECK_T=15$" && \
       echo "$result" | grep -q "^CHECKOV_T=60$"; then
        pass "config v2: timeout values parsed from config"
    else
        ERRORS="\n  Got: $result"
        fail "config v2: timeout values parsed from config"
    fi
}
test_config_v2_timeouts

# ── Env var overrides config for strict ──────────────────────────
test_config_v2_env_overrides_strict() {
    local tmpdir
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-strict-false.yml" "$tmpdir/.seatbelt.yml"

    local result
    result=$(cd "$tmpdir" && _unset_all_seatbelt_vars && export SEATBELT_STRICT=true && source "$CONFIG_SCRIPT" 2>/dev/null && printf 'STRICT=%s\n' "$SEATBELT_STRICT")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "^STRICT=true$"; then
        pass "config v2: env var overrides strict=false to true"
    else
        ERRORS="\n  Expected STRICT=true, got: $result"
        fail "config v2: env var overrides strict=false to true"
    fi
}
test_config_v2_env_overrides_strict

# ── Env var overrides severity (presence-based) ──────────────────
test_config_v2_env_overrides_severity() {
    local tmpdir
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-severity.yml" "$tmpdir/.seatbelt.yml"

    local result
    result=$(cd "$tmpdir" && _unset_all_seatbelt_vars && export SEATBELT_TRIVY_SEVERITY="" && source "$CONFIG_SCRIPT" 2>/dev/null && printf 'TRIVY_SEV=%s\n' "$SEATBELT_TRIVY_SEVERITY")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "^TRIVY_SEV=$"; then
        pass "config v2: empty env var clears config severity (presence-based)"
    else
        ERRORS="\n  Expected empty TRIVY_SEV, got: $result"
        fail "config v2: empty env var clears config severity (presence-based)"
    fi
}
test_config_v2_env_overrides_severity

# ── Full v6 config parses all fields ─────────────────────────────
test_config_v2_full_config() {
    local tmpdir
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-full-v6.yml" "$tmpdir/.seatbelt.yml"

    local result
    result=$(cd "$tmpdir" && _unset_all_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && \
        printf 'STRICT=%s\nTRIVY_SEV=%s\nSEMGREP_SEV=%s\nZIZMOR_SEV=%s\nRULESET=%s\nTRIVY_T=%s\nSEMGREP_T=%s\nSHELLCHECK_T=%s\nCHECKOV_T=%s\n' \
        "$SEATBELT_STRICT" "$SEATBELT_TRIVY_SEVERITY" "$SEATBELT_SEMGREP_SEVERITY" "$SEATBELT_ZIZMOR_SEVERITY" "$SEATBELT_SEMGREP_RULESET" "$SEATBELT_TRIVY_TIMEOUT" "$SEATBELT_SEMGREP_TIMEOUT" "$SEATBELT_SHELLCHECK_TIMEOUT" "$SEATBELT_CHECKOV_TIMEOUT")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "^STRICT=true$" && \
       echo "$result" | grep -q "^TRIVY_SEV=CRITICAL$" && \
       echo "$result" | grep -q "^SEMGREP_SEV=error$" && \
       echo "$result" | grep -q "^ZIZMOR_SEV=high$" && \
       echo "$result" | grep -q "^RULESET=p/owasp-top-ten$" && \
       echo "$result" | grep -q "^TRIVY_T=45$" && \
       echo "$result" | grep -q "^SEMGREP_T=90$" && \
       echo "$result" | grep -q "^SHELLCHECK_T=15$" && \
       echo "$result" | grep -q "^CHECKOV_T=60$"; then
        pass "config v2: full v6 config parses all fields"
    else
        ERRORS="\n  Got: $result"
        fail "config v2: full v6 config parses all fields"
    fi
}
test_config_v2_full_config

# ── Backward compat: v5-style config still works ─────────────────
test_config_v2_backward_compat() {
    local tmpdir
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-disabled-gitleaks.yml" "$tmpdir/.seatbelt.yml"

    local result
    result=$(cd "$tmpdir" && _unset_all_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && \
        printf 'GITLEAKS=%s\nSTRICT=%s\nTRIVY_SEV=%s\nRULESET=%s\n' \
        "$SEATBELT_GITLEAKS_ENABLED" "$SEATBELT_STRICT" "$SEATBELT_TRIVY_SEVERITY" "$SEATBELT_SEMGREP_RULESET")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "^GITLEAKS=false$" && \
       echo "$result" | grep -q "^STRICT=true$" && \
       echo "$result" | grep -q "^TRIVY_SEV=$" && \
       echo "$result" | grep -q "^RULESET=p/security-audit$"; then
        pass "config v2: v5-style config backward compatible"
    else
        ERRORS="\n  Got: $result"
        fail "config v2: v5-style config backward compatible"
    fi
}
test_config_v2_backward_compat
