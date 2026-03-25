# Tests for lib/config.sh
CONFIG_SCRIPT="$PROJECT_ROOT/hooks/scripts/lib/config.sh"

# Helper: unset any inherited SEATBELT_*_ENABLED vars to isolate tests
_unset_seatbelt_vars() {
    unset SEATBELT_GITLEAKS_ENABLED SEATBELT_CHECKOV_ENABLED SEATBELT_TRIVY_ENABLED SEATBELT_ZIZMOR_ENABLED SEATBELT_SEMGREP_ENABLED 2>/dev/null || true
}

# ── No config file -> all scanners enabled (defaults) ─────────────────
test_config_defaults_no_config_file() {
    local tmpdir result
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q

    result=$(cd "$tmpdir" && _unset_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && echo "GITLEAKS=$SEATBELT_GITLEAKS_ENABLED CHECKOV=$SEATBELT_CHECKOV_ENABLED TRIVY=$SEATBELT_TRIVY_ENABLED ZIZMOR=$SEATBELT_ZIZMOR_ENABLED SEMGREP=$SEATBELT_SEMGREP_ENABLED")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "GITLEAKS=true" && \
       echo "$result" | grep -q "CHECKOV=true" && \
       echo "$result" | grep -q "TRIVY=true" && \
       echo "$result" | grep -q "ZIZMOR=true" && \
       echo "$result" | grep -q "SEMGREP=true"; then
        pass "config defaults: no config file -> all enabled"
    else
        ERRORS="\n  Expected all scanners true, got: $result"
        fail "config defaults: no config file -> all enabled"
    fi
}
test_config_defaults_no_config_file

# ── Config disabling gitleaks -> gitleaks false, others true ──────────
test_config_disable_gitleaks() {
    local tmpdir result
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-disabled-gitleaks.yml" "$tmpdir/.seatbelt.yml"

    result=$(cd "$tmpdir" && _unset_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && echo "GITLEAKS=$SEATBELT_GITLEAKS_ENABLED CHECKOV=$SEATBELT_CHECKOV_ENABLED TRIVY=$SEATBELT_TRIVY_ENABLED ZIZMOR=$SEATBELT_ZIZMOR_ENABLED SEMGREP=$SEATBELT_SEMGREP_ENABLED")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "GITLEAKS=false" && \
       echo "$result" | grep -q "CHECKOV=true" && \
       echo "$result" | grep -q "TRIVY=true" && \
       echo "$result" | grep -q "ZIZMOR=true" && \
       echo "$result" | grep -q "SEMGREP=true"; then
        pass "config: gitleaks disabled, others default true"
    else
        ERRORS="\n  Expected GITLEAKS=false and others true, got: $result"
        fail "config: gitleaks disabled, others default true"
    fi
}
test_config_disable_gitleaks

# ── Config with all enabled -> all SEATBELT_*_ENABLED=true ───────────
test_config_all_enabled() {
    local tmpdir result
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-all-enabled.yml" "$tmpdir/.seatbelt.yml"

    result=$(cd "$tmpdir" && _unset_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && echo "GITLEAKS=$SEATBELT_GITLEAKS_ENABLED CHECKOV=$SEATBELT_CHECKOV_ENABLED TRIVY=$SEATBELT_TRIVY_ENABLED ZIZMOR=$SEATBELT_ZIZMOR_ENABLED SEMGREP=$SEATBELT_SEMGREP_ENABLED")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "GITLEAKS=true" && \
       echo "$result" | grep -q "CHECKOV=true" && \
       echo "$result" | grep -q "TRIVY=true" && \
       echo "$result" | grep -q "ZIZMOR=true" && \
       echo "$result" | grep -q "SEMGREP=true"; then
        pass "config: all scanners explicitly enabled"
    else
        ERRORS="\n  Expected all scanners true, got: $result"
        fail "config: all scanners explicitly enabled"
    fi
}
test_config_all_enabled

# ── Invalid YAML -> all scanners enabled (fail-open) ─────────────────
test_config_invalid_yaml() {
    local tmpdir result
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-invalid.yml" "$tmpdir/.seatbelt.yml"

    result=$(cd "$tmpdir" && _unset_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && echo "GITLEAKS=$SEATBELT_GITLEAKS_ENABLED CHECKOV=$SEATBELT_CHECKOV_ENABLED TRIVY=$SEATBELT_TRIVY_ENABLED ZIZMOR=$SEATBELT_ZIZMOR_ENABLED SEMGREP=$SEATBELT_SEMGREP_ENABLED")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "GITLEAKS=true" && \
       echo "$result" | grep -q "CHECKOV=true" && \
       echo "$result" | grep -q "TRIVY=true" && \
       echo "$result" | grep -q "ZIZMOR=true" && \
       echo "$result" | grep -q "SEMGREP=true"; then
        pass "config: invalid YAML -> fail-open, all enabled"
    else
        ERRORS="\n  Expected all scanners true (fail-open), got: $result"
        fail "config: invalid YAML -> fail-open, all enabled"
    fi
}
test_config_invalid_yaml

# ── Config without scanners key -> all enabled ───────────────────────
test_config_no_scanners_key() {
    local tmpdir result
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    echo "foo: bar" > "$tmpdir/.seatbelt.yml"

    result=$(cd "$tmpdir" && _unset_seatbelt_vars && source "$CONFIG_SCRIPT" 2>/dev/null && echo "GITLEAKS=$SEATBELT_GITLEAKS_ENABLED CHECKOV=$SEATBELT_CHECKOV_ENABLED TRIVY=$SEATBELT_TRIVY_ENABLED ZIZMOR=$SEATBELT_ZIZMOR_ENABLED SEMGREP=$SEATBELT_SEMGREP_ENABLED")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "GITLEAKS=true" && \
       echo "$result" | grep -q "CHECKOV=true" && \
       echo "$result" | grep -q "TRIVY=true" && \
       echo "$result" | grep -q "ZIZMOR=true" && \
       echo "$result" | grep -q "SEMGREP=true"; then
        pass "config: no scanners key -> all enabled"
    else
        ERRORS="\n  Expected all scanners true, got: $result"
        fail "config: no scanners key -> all enabled"
    fi
}
test_config_no_scanners_key

# ── Env var precedence: env var overrides config ─────────────────────
test_config_env_var_precedence() {
    local tmpdir result
    tmpdir=$(mktemp -d)
    git -C "$tmpdir" init -q
    cp "$FIXTURES_DIR/seatbelt-disabled-gitleaks.yml" "$tmpdir/.seatbelt.yml"

    result=$(cd "$tmpdir" && _unset_seatbelt_vars && export SEATBELT_GITLEAKS_ENABLED=true && source "$CONFIG_SCRIPT" 2>/dev/null && echo "GITLEAKS=$SEATBELT_GITLEAKS_ENABLED")
    rm -rf "$tmpdir"

    ERRORS=""
    if echo "$result" | grep -q "GITLEAKS=true"; then
        pass "config: env var overrides config (SEATBELT_GITLEAKS_ENABLED=true wins)"
    else
        ERRORS="\n  Expected GITLEAKS=true (env wins over config false), got: $result"
        fail "config: env var overrides config (SEATBELT_GITLEAKS_ENABLED=true wins)"
    fi
}
test_config_env_var_precedence
