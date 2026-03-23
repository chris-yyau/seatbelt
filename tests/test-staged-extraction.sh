#!/usr/bin/env bash
# Integration tests for staged-file extraction
# These tests create real git repos with staged content to verify
# scanners read from the index, not the working tree.

# ── Integration test helpers ──────────────────────────────────────

# Create a temp git repo with initial commit
# Usage: REPO=$(make_test_repo)
make_test_repo() {
    local repo
    repo=$(mktemp -d)
    git -C "$repo" init -q
    git -C "$repo" config user.email "test@test.com"
    git -C "$repo" config user.name "Test"
    git -C "$repo" config commit.gpgSign false
    # Need an initial commit so diff --cached works
    touch "$repo/.gitkeep"
    git -C "$repo" add .gitkeep
    git -C "$repo" commit -q -m "init"
    echo "$repo"
}

# Create a stub scanner that records what it received
# Usage: STUB=$(make_stub_scanner "checkov")
# The stub writes the file path and content it was given to $STUB.log
make_stub_scanner() {
    local name="$1"
    local stubdir
    stubdir=$(mktemp -d)
    local stub="$stubdir/$name"
    cat > "$stub" << 'STUBEOF'
#!/usr/bin/env bash
# Stub scanner — records file path + content to $0.log
echo "STUB_CALLED: $*" >> "$0.log"
prev=""
for arg in "$@"; do
    if [ "$prev" = "--file" ] && [ -f "$arg" ]; then
        echo "STUB_CONTENT: $(cat "$arg")" >> "$0.log"
    elif [ -f "$arg" ] && case "$arg" in /*) true;; */*) true;; *) false;; esac; then
        echo "STUB_CONTENT: $(cat "$arg")" >> "$0.log"
    fi
    prev="$arg"
done
exit 0
STUBEOF
    chmod +x "$stub"
    echo "$stub"
}

# Run a scanner hook inside a test repo
# Usage: run_hook_in_repo "$REPO" "scan-checkov.sh" "$FIXTURE" ["PATH_PREFIX"]
run_hook_in_repo() {
    local repo="$1"
    local script="$2"
    local fixture="$3"
    local path_prefix="${4:-}"

    # Reset state (mirrors run_hook_test in run-tests.sh)
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

# ── Test: zero-match extraction exits cleanly ─────────────────────
run_zero_match_test() {
    local repo
    repo=$(make_test_repo)

    # Stage a .js file (not an IaC file — no scanner should match)
    echo "console.log('hello')" > "$repo/app.js"
    git -C "$repo" add app.js

    run_hook_in_repo "$repo" "scan-checkov.sh" "$FIXTURES_DIR/git-commit.json"
    assert_exit_0 && assert_stdout_empty && pass "checkov: zero-match exits cleanly" || fail "checkov: zero-match exits cleanly"

    run_hook_in_repo "$repo" "scan-trivy.sh" "$FIXTURES_DIR/git-commit.json"
    assert_exit_0 && assert_stdout_empty && pass "trivy: zero-match exits cleanly" || fail "trivy: zero-match exits cleanly"

    run_hook_in_repo "$repo" "scan-zizmor.sh" "$FIXTURES_DIR/git-commit.json"
    assert_exit_0 && assert_stdout_empty && pass "zizmor: zero-match exits cleanly" || fail "zizmor: zero-match exits cleanly"

    rm -rf "$repo"
}
run_zero_match_test

# ── Test: checkov scans staged content, not working tree ──────────
run_checkov_staged_test() {
    local repo
    repo=$(make_test_repo)

    # Stage a Dockerfile with a unique STAGED marker
    cat > "$repo/Dockerfile" << 'EOF'
FROM ubuntu:latest
RUN echo STAGED_MARKER_ABC123
EOF
    git -C "$repo" add Dockerfile

    # Mutate working tree with a different WORKTREE marker
    cat > "$repo/Dockerfile" << 'EOF'
FROM ubuntu:latest
RUN echo WORKTREE_MARKER_XYZ789
EOF
    # Do NOT re-stage — staged version has STAGED_MARKER_ABC123

    local stub stubdir
    stub=$(make_stub_scanner "checkov")
    stubdir=$(dirname "$stub")
    run_hook_in_repo "$repo" "scan-checkov.sh" "$FIXTURES_DIR/git-commit.json" "$stubdir"

    # Verify stub was called and received the STAGED content (not working tree)
    if [ -f "$stub.log" ] && grep -q "STUB_CALLED" "$stub.log"; then
        if grep -q "STAGED_MARKER_ABC123" "$stub.log" && ! grep -q "WORKTREE_MARKER_XYZ789" "$stub.log"; then
            pass "checkov: scans staged content, not working tree"
        else
            fail "checkov: should see STAGED_MARKER, not WORKTREE_MARKER"
        fi
    else
        fail "checkov: stub scanner was not invoked"
    fi

    [ -n "$repo" ] && rm -rf "$repo"
    [ -n "$stubdir" ] && rm -rf "$stubdir"
}
run_checkov_staged_test

# ── Test: trivy scans staged content, not working tree ────────────
run_trivy_staged_test() {
    local repo
    repo=$(make_test_repo)

    # Stage a package-lock.json with specific content
    echo '{"name":"test","lockfileVersion":2,"dependencies":{"bad-pkg":"1.0.0"}}' > "$repo/package-lock.json"
    git -C "$repo" add package-lock.json

    # Mutate working tree
    echo '{"name":"test","lockfileVersion":2,"dependencies":{"good-pkg":"2.0.0"}}' > "$repo/package-lock.json"

    # Provision fake trivy DB cache (scan-trivy.sh checks this before scanning)
    local fake_cache
    fake_cache=$(mktemp -d)
    mkdir -p "$fake_cache/db"
    touch "$fake_cache/db/placeholder"

    local stub
    stub=$(make_stub_scanner "trivy")
    TRIVY_CACHE_DIR="$fake_cache" run_hook_in_repo "$repo" "scan-trivy.sh" "$FIXTURES_DIR/git-commit.json" "$(dirname "$stub")"

    if [ -f "$stub.log" ] && grep -q "STUB_CALLED" "$stub.log"; then
        if grep -q "bad-pkg" "$stub.log" && ! grep -q "good-pkg" "$stub.log"; then
            pass "trivy: scans staged content, not working tree"
        elif grep -q "good-pkg" "$stub.log"; then
            fail "trivy: scanned working tree content (good-pkg) instead of staged"
        else
            fail "trivy: should see staged content (bad-pkg), not working tree"
        fi
    else
        fail "trivy: stub scanner was not invoked"
    fi

    rm -rf "$repo" "$(dirname "$stub")" "$fake_cache"
}
run_trivy_staged_test

# ── Test: zizmor scans staged content, not working tree ───────────
run_zizmor_staged_test() {
    local repo
    repo=$(make_test_repo)

    # Stage a workflow with known content
    mkdir -p "$repo/.github/workflows"
    echo 'name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3' > "$repo/.github/workflows/ci.yml"
    git -C "$repo" add .github/workflows/ci.yml

    # Mutate working tree (pin the action)
    echo 'name: ci
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@8ade135a41bc03ea155e62e844d188df1ea18608' > "$repo/.github/workflows/ci.yml"

    local stub
    stub=$(make_stub_scanner "zizmor")
    run_hook_in_repo "$repo" "scan-zizmor.sh" "$FIXTURES_DIR/git-commit.json" "$(dirname "$stub")"

    if [ -f "$stub.log" ] && grep -q "STUB_CALLED" "$stub.log"; then
        # Staged version uses @v3 (unpinned), working tree uses pinned SHA
        if grep -q "actions/checkout@v3" "$stub.log"; then
            pass "zizmor: scans staged content, not working tree"
        else
            fail "zizmor: should see staged content (@v3), not working tree"
        fi
    else
        fail "zizmor: stub scanner was not invoked"
    fi

    rm -rf "$repo" "$(dirname "$stub")"
}
run_zizmor_staged_test
