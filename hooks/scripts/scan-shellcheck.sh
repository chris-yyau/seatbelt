#!/usr/bin/env bash
# Seatbelt: scan staged shell scripts for quality issues before git commit
# Scanner: shellcheck | Fail mode: warn only (never blocks)
# Skip: SKIP_SHELLCHECK=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_SHELLCHECK:-0}" = "1" ] && exit 0

# ── Detect git commit via shared library ─────────────────────────
# shellcheck disable=SC2034  # HOOK_DATA is consumed by sourced detect-commit.sh
HOOK_DATA=$(cat 2>/dev/null || true)
LIB_DIR="$(cd "$(dirname "$0")" && pwd)/lib"
# shellcheck disable=SC1091
if ! source "$LIB_DIR/detect-commit.sh"; then
    echo "SEATBELT DEGRADED: shellcheck commit detection unavailable — shellcheck scan skipped" >&2
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
rm -f "$SEATBELT_RESULT_DIR/shellcheck"

# ── Config file override ─────────────────────────────────────────
# shellcheck disable=SC1091
source "$LIB_DIR/config.sh"
[ "$SEATBELT_SHELLCHECK_ENABLED" = "false" ] && exit 0

# ── shellcheck availability ─────────────────────────────────────────
if ! command -v shellcheck &>/dev/null; then
    echo "SEATBELT DEGRADED: shellcheck not installed — shell script linting DISABLED (brew install shellcheck | /seatbelt:doctor)" >&2
    exit 0
fi

# ── Early exit: no shell scripts staged ──────────────────────────
HAS_SHELL_SCRIPTS=0
while IFS= read -r -d '' path; do
    case "$path" in
        *.sh|*.bash) HAS_SHELL_SCRIPTS=1; break ;;
    esac
done < <(git diff -z --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
[ "$HAS_SHELL_SCRIPTS" -eq 0 ] && exit 0

# ── Extract staged shell scripts to temp dir ─────────────────────
SCAN_DIR=$(mktemp -d)
trap 'rm -rf "$SCAN_DIR"' EXIT

# ── Portable timeout ───────────────────────────────────────────────
TIMEOUT_CMD=""
if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout 30"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout 30"
fi

EXTRACTED=0
EXPECTED=0
while IFS= read -r -d '' sf; do
    [ -z "$sf" ] && continue

    case "$sf" in
        *.sh|*.bash) ;;
        *)           continue ;;
    esac

    local_mode=$(git ls-files -s -- "$sf" 2>/dev/null | cut -d' ' -f1)
    if [ "$local_mode" = "120000" ] || [ "$local_mode" = "160000" ]; then continue; fi

    EXPECTED=$((EXPECTED + 1))
    mkdir -p "$SCAN_DIR/$(dirname "$sf")" 2>/dev/null || continue
    git show ":$sf" > "$SCAN_DIR/$sf" 2>/dev/null || continue
    EXTRACTED=$((EXTRACTED + 1))

    if [ -n "$TIMEOUT_CMD" ]; then
        SCAN_OUTPUT=$($TIMEOUT_CMD shellcheck --format=json1 "$SCAN_DIR/$sf" 2>&1) || true
    else
        SCAN_OUTPUT=$(shellcheck --format=json1 "$SCAN_DIR/$sf" 2>&1) || true
    fi

    # Parse JSON for findings
    # json1 schema: {"comments":[{"file":"...","line":N,"column":N,"level":"error|warning|info|style","code":N,"message":"..."}]}
    FINDING_INFO=$(printf '%s' "$SCAN_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    comments = data.get('comments', []) or []
    count = len(comments)
    summary_lines = []
    for c in comments[:5]:
        code = c.get('code', '')
        level = c.get('level', '')
        line = c.get('line', '')
        message = c.get('message', '')
        summary_lines.append(f'  SC{code} [{level}] line {line}: {message}')
    summary = '\n'.join(summary_lines)
    print(f'{count}|{summary}')
except Exception:
    print('-1|')
" 2>/dev/null || echo "-1|")

    FINDING_COUNT="${FINDING_INFO%%|*}"
    FINDING_SUMMARY="${FINDING_INFO#*|}"

    if [ "$FINDING_COUNT" = "-1" ]; then
        echo "SEATBELT: shellcheck: could not parse scan output for $(basename "$sf") — scan result unknown" >&2
    elif [ "$FINDING_COUNT" -gt 0 ] 2>/dev/null; then
        echo "SEATBELT: shellcheck found ${FINDING_COUNT} issue(s) in $(basename "$sf"):" >&2
        if [ -n "$FINDING_SUMMARY" ]; then
            printf '%s\n' "$FINDING_SUMMARY" >&2
        fi
        # Write result for summary aggregation (append: multiple scripts may have findings)
        mkdir -p "$SEATBELT_RESULT_DIR"
        echo "${FINDING_COUNT} issue(s) in $(basename "$sf")" >> "$SEATBELT_RESULT_DIR/shellcheck"
    fi
done < <(git diff -z --cached --name-only --diff-filter=ACMR 2>/dev/null)

[ "$EXPECTED" -eq 0 ] && exit 0

if [ "$EXTRACTED" -lt "$EXPECTED" ]; then
    echo "SEATBELT: shellcheck: extracted $EXTRACTED/$EXPECTED staged files (some skipped)" >&2
fi

exit 0
