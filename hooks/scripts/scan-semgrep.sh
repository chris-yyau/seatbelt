#!/usr/bin/env bash
# Seatbelt: scan staged source files for security vulnerabilities before git commit
# Scanner: semgrep | Fail mode: warn only (blocks when severity threshold configured)
# Skip: SKIP_SEMGREP=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_SEMGREP:-0}" = "1" ] && exit 0

# ── Detect git commit via shared library ─────────────────────────
# shellcheck disable=SC2034  # HOOK_DATA is consumed by sourced detect-commit.sh
HOOK_DATA=$(cat 2>/dev/null || true)
LIB_DIR="$(cd "$(dirname "$0")" && pwd)/lib"
# shellcheck disable=SC1091
if ! source "$LIB_DIR/detect-commit.sh"; then
    echo "SEATBELT DEGRADED: semgrep commit detection unavailable — semgrep scan skipped" >&2
    exit 0
fi
[ "$IS_GIT_COMMIT" != "yes" ] && exit 0
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# ── Clean stale results from a previous blocked commit ───────────
# PreToolUse scanners write results, but if a blocking scanner prevents the
# commit, the PostToolUse summary hook never fires and stale files persist.
# Clean unconditionally on every commit attempt, before any early exits.
# shellcheck disable=SC1091
source "$LIB_DIR/result-dir.sh"
rm -f "$SEATBELT_RESULT_DIR/semgrep"

# ── Config file override ─────────────────────────────────────────
# shellcheck disable=SC1091
source "$LIB_DIR/config.sh"
[ "$SEATBELT_SEMGREP_ENABLED" = "false" ] && exit 0
# shellcheck disable=SC1091
source "$LIB_DIR/block-emit.sh"
# Validate severity threshold if configured
if [ -n "${SEATBELT_SEMGREP_SEVERITY:-}" ]; then
    _seatbelt_validate_severity "semgrep" "$SEATBELT_SEMGREP_SEVERITY" "info,warning,error" || SEATBELT_SEMGREP_SEVERITY=""
fi
SEMGREP_RULESET="${SEATBELT_SEMGREP_RULESET:-p/security-audit}"

# ── semgrep availability ──────────────────────────────────────────
if ! command -v semgrep &>/dev/null; then
    echo "SEATBELT DEGRADED: semgrep not installed — source code scanning DISABLED (pip3 install semgrep | /seatbelt:doctor)" >&2
    exit 0
fi

# ── Extract staged source files to temp dir ──────────────────────
SCAN_DIR=$(mktemp -d)
trap 'rm -rf "$SCAN_DIR"' EXIT

# ── Portable timeout (config-driven) ────────────────────────────
TIMEOUT_CMD=""
if [ -n "${SEATBELT_SEMGREP_TIMEOUT:-}" ]; then
    if command -v timeout &>/dev/null; then
        TIMEOUT_CMD="timeout $SEATBELT_SEMGREP_TIMEOUT"
    elif command -v gtimeout &>/dev/null; then
        TIMEOUT_CMD="gtimeout $SEATBELT_SEMGREP_TIMEOUT"
    fi
fi

EXTRACTED=0
EXPECTED=0
while IFS= read -r -d '' sf; do
    [ -z "$sf" ] && continue

    # Filter: only source code files that semgrep can scan
    case "$sf" in
        *.py|*.js|*.ts|*.jsx|*.tsx|*.java|*.go|*.rb|*.php) ;;
        *.c|*.cpp|*.cs|*.rs|*.swift|*.kt|*.scala)          ;;
        *.yaml|*.yml)                                        ;;
        *)                                                   continue ;;
    esac

    # Skip symlinks and submodules
    local_mode=$(git ls-files -s -- "$sf" 2>/dev/null | cut -d' ' -f1)
    if [ "$local_mode" = "120000" ] || [ "$local_mode" = "160000" ]; then continue; fi

    EXPECTED=$((EXPECTED + 1))
    mkdir -p "$SCAN_DIR/$(dirname "$sf")" 2>/dev/null || continue
    git show ":$sf" > "$SCAN_DIR/$sf" 2>/dev/null || continue
    EXTRACTED=$((EXTRACTED + 1))
done < <(git diff -z --cached --name-only --diff-filter=ACMR 2>/dev/null || true)

[ "$EXPECTED" -eq 0 ] && exit 0

if [ "$EXTRACTED" -lt "$EXPECTED" ]; then
    echo "SEATBELT: semgrep: extracted $EXTRACTED/$EXPECTED staged files (some skipped)" >&2
fi

# ── Run semgrep scan ─────────────────────────────────────────────
SCAN_OUTPUT=""
SCAN_STDERR_FILE="$SCAN_DIR/.semgrep_stderr"
SCAN_EXIT=0
if [ -n "$TIMEOUT_CMD" ]; then
    SCAN_OUTPUT=$($TIMEOUT_CMD semgrep scan --config "$SEMGREP_RULESET" --json --quiet "$SCAN_DIR" 2>"$SCAN_STDERR_FILE") || SCAN_EXIT=$?
else
    SCAN_OUTPUT=$(semgrep scan --config "$SEMGREP_RULESET" --json --quiet "$SCAN_DIR" 2>"$SCAN_STDERR_FILE") || SCAN_EXIT=$?
fi

# Detect timeout (exit 124 from coreutils timeout, 137 from SIGKILL)
if [ "$SCAN_EXIT" -eq 124 ] || [ "$SCAN_EXIT" -eq 137 ]; then
    echo "SEATBELT DEGRADED: semgrep timed out after ${SEATBELT_SEMGREP_TIMEOUT}s — scan skipped" >&2
    exit 0
fi

# Check for invalid ruleset or other CLI failure with no JSON output
if [ -z "$SCAN_OUTPUT" ] && [ -f "$SCAN_STDERR_FILE" ]; then
    if grep -qiE '(invalid|not found|error.*config|could not resolve)' "$SCAN_STDERR_FILE" 2>/dev/null; then
        echo "SEATBELT DEGRADED: semgrep invalid ruleset '${SEMGREP_RULESET}' — scan skipped" >&2
        exit 0
    fi
    # Non-zero exit with no JSON and no known error pattern — CLI failure
    if [ "$SCAN_EXIT" -ne 0 ]; then
        echo "SEATBELT DEGRADED: semgrep exited with code ${SCAN_EXIT} — scan skipped" >&2
        exit 0
    fi
fi

# ── Parse JSON for findings ──────────────────────────────────────
FINDING_INFO=$(printf '%s' "$SCAN_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('results', []) or []
    count = len(results)
    summary_lines = []
    for r in results[:5]:
        check_id = r.get('check_id', '')
        severity = r.get('extra', {}).get('severity', '')
        path = r.get('path', '')
        line = r.get('start', {}).get('line', '')
        summary_lines.append(f'  {check_id} [{severity}] {path}:{line}')
    summary = '; '.join(summary_lines)
    print(f'{count}|{summary}')
except Exception:
    print('-1|')
" 2>/dev/null || echo "-1|")

FINDING_COUNT="${FINDING_INFO%%|*}"
FINDING_SUMMARY="${FINDING_INFO#*|}"

if [ "$FINDING_COUNT" = "-1" ]; then
    if [ -n "$SCAN_OUTPUT" ]; then
        echo "SEATBELT: semgrep: could not parse scan output — scan result unknown" >&2
    fi
elif [ "$FINDING_COUNT" -gt 0 ] 2>/dev/null; then
    echo "SEATBELT: semgrep found ${FINDING_COUNT} finding(s):" >&2
    if [ -n "$FINDING_SUMMARY" ]; then
        # Strip temp dir prefix from paths for clean output (bash substitution avoids sed regex issues with dots in paths)
        CLEAN_SUMMARY="${FINDING_SUMMARY//$SCAN_DIR\//}"
        printf '%s\n' "$CLEAN_SUMMARY" >&2
    fi
    # Write result for summary aggregation
    mkdir -p "$SEATBELT_RESULT_DIR"
    echo "${FINDING_COUNT} finding(s)" > "$SEATBELT_RESULT_DIR/semgrep"

    # Severity gating: if threshold configured, check if any finding meets it
    if [ -n "${SEATBELT_SEMGREP_SEVERITY:-}" ]; then
        _semgrep_has_blocking=$(printf '%s' "$SCAN_OUTPUT" | SEATBELT_SEMGREP_SEVERITY="$SEATBELT_SEMGREP_SEVERITY" python3 -c "
import sys, json, os
try:
    data = json.load(sys.stdin)
    threshold = os.environ.get('SEATBELT_SEMGREP_SEVERITY', '').lower()
    scale = ['info', 'warning', 'error']
    if threshold not in scale:
        sys.exit(0)
    ti = scale.index(threshold)
    for r in data.get('results', []) or []:
        sev = r.get('extra', {}).get('severity', '').lower()
        if sev in scale and scale.index(sev) >= ti:
            print('yes')
            sys.exit(0)
except Exception:
    pass
" 2>/dev/null || true)
        if [ "$_semgrep_has_blocking" = "yes" ]; then
            block_emit "semgrep" "${FINDING_COUNT} finding(s) at or above ${SEATBELT_SEMGREP_SEVERITY} severity"
        fi
        unset _semgrep_has_blocking
    fi
fi

exit 0
