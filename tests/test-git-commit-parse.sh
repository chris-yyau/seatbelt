# shellcheck shell=bash disable=SC2034  # sourced by run-tests.sh; ERRORS is read by the shared fail()
# Tests for lib/git_commit_parse.py (shared git-commit command parser)
# The module ships an assert-based self-check in its __main__; run it here so
# CI catches parser regressions (option-prefixed forms, quoted operators,
# command/builtin wrappers, inspection vs execution).
PARSE_LIB="$PROJECT_ROOT/hooks/scripts/lib/git_commit_parse.py"

test_git_commit_parse_selfcheck() {
    ERRORS=""
    local out
    out=$(python3 "$PARSE_LIB" 2>&1)
    case "$out" in
        *"self-check ok"*) pass "git_commit_parse self-check passes" ;;
        *) ERRORS="\n  $out"; fail "git_commit_parse self-check passes" ;;
    esac
}
test_git_commit_parse_selfcheck
