#!/usr/bin/env bash
# Integration tests for JSON output parsing in scan-checkov.sh, scan-trivy.sh, scan-zizmor.sh
# These tests use mock scanner binaries to verify structured JSON parsing and grep fallback.

# ── Local helpers (duplicated from test-staged-extraction.sh to ensure correct sort order) ──

_zjp_make_test_repo() {
    local repo
    repo=$(mktemp -d)
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@test.com"
    git -C "$repo" config user.name "Test"
    git -C "$repo" config commit.gpgSign false
    touch "$repo/.gitkeep"
    git -C "$repo" add .gitkeep
    git -C "$repo" commit -q -m "init"
    echo "$repo"
}

_zjp_run_hook_in_repo() {
    local repo="$1"
    local script="$2"
    local fixture="$3"
    local path_prefix="${4:-}"

    ERRORS=""
    STDOUT=""
    STDERR=""
    EXIT_CODE=0

    local tmpout tmperr
    tmpout=$(mktemp)
    tmperr=$(mktemp)

    local old_path="$PATH"
    if [ -n "$path_prefix" ]; then
        PATH="$path_prefix:$PATH"
    fi

    (cd "$repo" && cat "$fixture" | bash "$PROJECT_ROOT/hooks/scripts/$script" >"$tmpout" 2>"$tmperr") || true

    PATH="$old_path"
    STDOUT=$(cat "$tmpout" 2>/dev/null || true)
    STDERR=$(cat "$tmperr" 2>/dev/null || true)
    rm -f "$tmpout" "$tmperr"
}

# ═══════════════════════════════════════════════════════════
# Task 4: scan-checkov.sh JSON parsing tests
# ═══════════════════════════════════════════════════════════

# Test 1: mock checkov returns JSON with 1 failed check → should BLOCK
test_checkov_json_finds_failures() {
    local repo mockdir
    repo=$(_zjp_make_test_repo)
    mockdir=$(mktemp -d)

    # Stage a Dockerfile so checkov has a file to scan
    cat > "$repo/Dockerfile" << 'EOF'
FROM ubuntu:latest
RUN echo hello
EOF
    git -C "$repo" add Dockerfile

    # Mock checkov: outputs JSON with 1 failed check
    cat > "$mockdir/checkov" << 'MOCKEOF'
#!/usr/bin/env bash
cat << 'JSON'
{
  "results": {
    "passed_checks": [],
    "failed_checks": [
      {
        "check_id": "CKV_DOCKER_2",
        "check_result": {"result": "FAILED"},
        "resource": "HEALTHCHECK",
        "file_path": "/tmp/Dockerfile",
        "file_line_range": [1, 2]
      }
    ]
  }
}
JSON
exit 0
MOCKEOF
    chmod +x "$mockdir/checkov"

    ERRORS=""
    _zjp_run_hook_in_repo "$repo" "scan-checkov.sh" "$FIXTURES_DIR/git-commit.json" "$mockdir"

    assert_stdout_json_block && \
        pass "checkov: JSON parsing finds failures and blocks" || \
        fail "checkov: JSON parsing finds failures and blocks"

    rm -rf "$repo" "$mockdir"
}
test_checkov_json_finds_failures

# Test 2: mock returns invalid JSON but text contains "FAILED" → grep fallback should BLOCK
test_checkov_json_fallback_on_malformed() {
    local repo mockdir
    repo=$(_zjp_make_test_repo)
    mockdir=$(mktemp -d)

    cat > "$repo/Dockerfile" << 'EOF'
FROM ubuntu:latest
RUN echo hello
EOF
    git -C "$repo" add Dockerfile

    # Mock checkov: outputs malformed JSON but text contains FAILED
    cat > "$mockdir/checkov" << 'MOCKEOF'
#!/usr/bin/env bash
echo "this is not valid json FAILED CKV_DOCKER_2 on /tmp/Dockerfile"
exit 0
MOCKEOF
    chmod +x "$mockdir/checkov"

    ERRORS=""
    _zjp_run_hook_in_repo "$repo" "scan-checkov.sh" "$FIXTURES_DIR/git-commit.json" "$mockdir"

    assert_stdout_json_block && \
        pass "checkov: malformed JSON falls back to grep and blocks" || \
        fail "checkov: malformed JSON falls back to grep and blocks"

    rm -rf "$repo" "$mockdir"
}
test_checkov_json_fallback_on_malformed

# Test 3: mock returns JSON with empty failed_checks → should NOT block
test_checkov_json_clean_scan() {
    local repo mockdir
    repo=$(_zjp_make_test_repo)
    mockdir=$(mktemp -d)

    cat > "$repo/Dockerfile" << 'EOF'
FROM ubuntu:latest
RUN echo hello
EOF
    git -C "$repo" add Dockerfile

    # Mock checkov: outputs JSON with empty failed_checks
    cat > "$mockdir/checkov" << 'MOCKEOF'
#!/usr/bin/env bash
cat << 'JSON'
{
  "results": {
    "passed_checks": [
      {"check_id": "CKV_DOCKER_1"}
    ],
    "failed_checks": []
  }
}
JSON
exit 0
MOCKEOF
    chmod +x "$mockdir/checkov"

    ERRORS=""
    _zjp_run_hook_in_repo "$repo" "scan-checkov.sh" "$FIXTURES_DIR/git-commit.json" "$mockdir"

    assert_stdout_no_block && \
        pass "checkov: clean JSON scan does not block" || \
        fail "checkov: clean JSON scan does not block"

    rm -rf "$repo" "$mockdir"
}
test_checkov_json_clean_scan

# ═══════════════════════════════════════════════════════════
# Task 5: scan-trivy.sh JSON parsing tests
# ═══════════════════════════════════════════════════════════

# Test 4: mock trivy returns JSON with 1 vuln → should warn on stderr
test_trivy_json_finds_vulns() {
    local repo mockdir fake_cache
    repo=$(_zjp_make_test_repo)
    mockdir=$(mktemp -d)
    fake_cache=$(mktemp -d)
    mkdir -p "$fake_cache/db"
    touch "$fake_cache/db/placeholder"

    echo '{"name":"test","lockfileVersion":2,"packages":{}}' > "$repo/package-lock.json"
    git -C "$repo" add package-lock.json

    # Mock trivy: outputs JSON with 1 vulnerability
    cat > "$mockdir/trivy" << 'MOCKEOF'
#!/usr/bin/env bash
cat << 'JSON'
{
  "SchemaVersion": 2,
  "Results": [
    {
      "Target": "package-lock.json",
      "Type": "npm",
      "Vulnerabilities": [
        {
          "VulnerabilityID": "CVE-2023-1234",
          "PkgName": "lodash",
          "InstalledVersion": "4.17.20",
          "Severity": "HIGH",
          "Title": "Prototype Pollution"
        }
      ]
    }
  ]
}
JSON
exit 0
MOCKEOF
    chmod +x "$mockdir/trivy"

    ERRORS=""
    export TRIVY_CACHE_DIR="$fake_cache"
    _zjp_run_hook_in_repo "$repo" "scan-trivy.sh" "$FIXTURES_DIR/git-commit.json" "$mockdir"
    unset TRIVY_CACHE_DIR

    if echo "$STDERR" | grep -qF "SEATBELT: trivy found"; then
        pass "trivy: JSON parsing finds vulns and warns on stderr"
    else
        ERRORS="${ERRORS}\n  Expected stderr to contain 'SEATBELT: trivy found'"
        fail "trivy: JSON parsing finds vulns and warns on stderr"
    fi

    rm -rf "$repo" "$mockdir" "$fake_cache"
}
test_trivy_json_finds_vulns

# Test 5: mock trivy returns JSON with null Vulnerabilities → should NOT warn
test_trivy_json_clean_scan() {
    local repo mockdir fake_cache
    repo=$(_zjp_make_test_repo)
    mockdir=$(mktemp -d)
    fake_cache=$(mktemp -d)
    mkdir -p "$fake_cache/db"
    touch "$fake_cache/db/placeholder"

    echo '{"name":"test","lockfileVersion":2,"packages":{}}' > "$repo/package-lock.json"
    git -C "$repo" add package-lock.json

    # Mock trivy: outputs JSON with null Vulnerabilities (common when no vulns found)
    cat > "$mockdir/trivy" << 'MOCKEOF'
#!/usr/bin/env bash
cat << 'JSON'
{
  "SchemaVersion": 2,
  "Results": [
    {
      "Target": "package-lock.json",
      "Type": "npm",
      "Vulnerabilities": null
    }
  ]
}
JSON
exit 0
MOCKEOF
    chmod +x "$mockdir/trivy"

    ERRORS=""
    export TRIVY_CACHE_DIR="$fake_cache"
    _zjp_run_hook_in_repo "$repo" "scan-trivy.sh" "$FIXTURES_DIR/git-commit.json" "$mockdir"
    unset TRIVY_CACHE_DIR

    assert_stdout_no_block
    if echo "$STDERR" | grep -qF "SEATBELT: trivy found"; then
        ERRORS="${ERRORS}\n  Expected stderr NOT to contain 'SEATBELT: trivy found'"
        fail "trivy: clean JSON scan does not warn"
    else
        pass "trivy: clean JSON scan does not warn"
    fi

    rm -rf "$repo" "$mockdir" "$fake_cache"
}
test_trivy_json_clean_scan

# Test: trivy malformed JSON → should emit degraded warning on stderr (fail-open)
test_trivy_json_parse_failure() {
    local repo mockdir fake_cache
    repo=$(_zjp_make_test_repo)
    mockdir=$(mktemp -d)
    fake_cache=$(mktemp -d)
    mkdir -p "$fake_cache/db"
    touch "$fake_cache/db/placeholder"

    echo '{"name":"test","lockfileVersion":2,"packages":{}}' > "$repo/package-lock.json"
    git -C "$repo" add package-lock.json

    # Mock trivy: outputs malformed JSON
    cat > "$mockdir/trivy" << 'MOCKEOF'
#!/usr/bin/env bash
echo "this is not valid json at all"
exit 0
MOCKEOF
    chmod +x "$mockdir/trivy"

    ERRORS=""
    export TRIVY_CACHE_DIR="$fake_cache"
    _zjp_run_hook_in_repo "$repo" "scan-trivy.sh" "$FIXTURES_DIR/git-commit.json" "$mockdir"
    unset TRIVY_CACHE_DIR

    if echo "$STDERR" | grep -qF "SEATBELT: trivy: could not parse"; then
        pass "trivy: malformed JSON emits degraded warning (fail-open)"
    else
        ERRORS="${ERRORS}\n  Expected stderr to contain 'SEATBELT: trivy: could not parse'"
        fail "trivy: malformed JSON emits degraded warning (fail-open)"
    fi

    rm -rf "$repo" "$mockdir" "$fake_cache"
}
test_trivy_json_parse_failure

# Test: checkov multi-framework list aggregates all items
test_checkov_multi_framework_list() {
    local repo mockdir
    repo=$(_zjp_make_test_repo)
    mockdir=$(mktemp -d)

    cat > "$repo/Dockerfile" << 'EOF'
FROM ubuntu:latest
RUN echo hello
EOF
    git -C "$repo" add Dockerfile

    # Mock checkov: outputs a list with multiple framework results (2 failed checks across 2 items)
    cat > "$mockdir/checkov" << 'MOCKEOF'
#!/usr/bin/env bash
cat << 'JSON'
[
  {
    "check_type": "dockerfile",
    "results": {
      "passed_checks": [],
      "failed_checks": [
        {"check_id": "CKV_DOCKER_2", "check_result": {"result": "FAILED"}, "resource": "HEALTHCHECK", "file_path": "/tmp/Dockerfile", "file_line_range": [1, 2]}
      ]
    }
  },
  {
    "check_type": "sca_image",
    "results": {
      "passed_checks": [],
      "failed_checks": [
        {"check_id": "CKV_DOCKER_3", "check_result": {"result": "FAILED"}, "resource": "ubuntu:latest", "file_path": "/tmp/Dockerfile", "file_line_range": [1, 1]}
      ]
    }
  }
]
JSON
exit 0
MOCKEOF
    chmod +x "$mockdir/checkov"

    ERRORS=""
    _zjp_run_hook_in_repo "$repo" "scan-checkov.sh" "$FIXTURES_DIR/git-commit.json" "$mockdir"

    assert_stdout_json_block && \
        pass "checkov: multi-framework list aggregates all failed checks" || \
        fail "checkov: multi-framework list aggregates all failed checks"

    rm -rf "$repo" "$mockdir"
}
test_checkov_multi_framework_list

# ═══════════════════════════════════════════════════════════
# Task 6: scan-zizmor.sh JSON parsing tests
# ═══════════════════════════════════════════════════════════

# Test 6: mock zizmor returns JSON array with 1 finding → should warn on stderr
test_zizmor_json_finds_issues() {
    local repo mockdir
    repo=$(_zjp_make_test_repo)
    mockdir=$(mktemp -d)

    mkdir -p "$repo/.github/workflows"
    cat > "$repo/.github/workflows/ci.yml" << 'EOF'
name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
EOF
    git -C "$repo" add .github/workflows/ci.yml

    # Mock zizmor: outputs JSON array with 1 finding (real v1 schema)
    cat > "$mockdir/zizmor" << 'MOCKEOF'
#!/usr/bin/env bash
cat << 'JSON'
[
  {
    "ident": "unpinned-uses",
    "desc": "unpinned action reference",
    "url": "https://docs.zizmor.sh/audits/#unpinned-uses",
    "determinations": {
      "confidence": "High",
      "severity": "Medium",
      "persona": "Regular"
    },
    "locations": [
      {
        "symbolic": {
          "key": {
            "Local": {
              "prefix": null,
              "given_path": ".github/workflows/ci.yml"
            }
          },
          "annotation": "uses unpinned action",
          "kind": "Primary"
        }
      }
    ],
    "ignored": false
  }
]
JSON
exit 1
MOCKEOF
    chmod +x "$mockdir/zizmor"

    ERRORS=""
    _zjp_run_hook_in_repo "$repo" "scan-zizmor.sh" "$FIXTURES_DIR/git-commit.json" "$mockdir"

    if echo "$STDERR" | grep -qF "SEATBELT: zizmor found"; then
        pass "zizmor: JSON parsing finds issues and warns on stderr"
    else
        ERRORS="${ERRORS}\n  Expected stderr to contain 'SEATBELT: zizmor found'"
        fail "zizmor: JSON parsing finds issues and warns on stderr"
    fi

    rm -rf "$repo" "$mockdir"
}
test_zizmor_json_finds_issues

# Test 7: mock zizmor ignores --format flag, outputs text → grep fallback should warn
test_zizmor_json_fallback_on_no_json_support() {
    local repo mockdir
    repo=$(_zjp_make_test_repo)
    mockdir=$(mktemp -d)

    mkdir -p "$repo/.github/workflows"
    cat > "$repo/.github/workflows/ci.yml" << 'EOF'
name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
EOF
    git -C "$repo" add .github/workflows/ci.yml

    # Mock zizmor: ignores --format flag, outputs plain text with warning pattern
    cat > "$mockdir/zizmor" << 'MOCKEOF'
#!/usr/bin/env bash
echo "warning[unpinned-uses]: unpinned action reference at .github/workflows/ci.yml:8:9"
exit 1
MOCKEOF
    chmod +x "$mockdir/zizmor"

    ERRORS=""
    _zjp_run_hook_in_repo "$repo" "scan-zizmor.sh" "$FIXTURES_DIR/git-commit.json" "$mockdir"

    if echo "$STDERR" | grep -qF "SEATBELT: zizmor found"; then
        pass "zizmor: text output fallback warns on stderr"
    else
        ERRORS="${ERRORS}\n  Expected stderr to contain 'SEATBELT: zizmor found'"
        fail "zizmor: text output fallback warns on stderr"
    fi

    rm -rf "$repo" "$mockdir"
}
test_zizmor_json_fallback_on_no_json_support
