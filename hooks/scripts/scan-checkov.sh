#!/usr/bin/env bash
# Seatbelt: scan staged IaC files for misconfigurations before git commit
# Scanner: checkov | Fail mode: BLOCK on findings, fail-open on errors
# Skip: SKIP_CHECKOV=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_CHECKOV:-0}" = "1" ] && exit 0

# ── Detect git commit via shared library ─────────────────────────
# shellcheck disable=SC2034  # HOOK_DATA is consumed by sourced detect-commit.sh
HOOK_DATA=$(cat 2>/dev/null || true)
LIB_DIR="$(cd "$(dirname "$0")" && pwd)/lib"
# shellcheck disable=SC1091
if ! source "$LIB_DIR/detect-commit.sh"; then
    echo "SEATBELT DEGRADED: checkov commit detection unavailable — checkov scan skipped" >&2
    exit 0
fi
[ "$IS_GIT_COMMIT" != "yes" ] && exit 0
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# ── Clean stale results from a previous blocked commit ───────────
# shellcheck disable=SC1091
source "$LIB_DIR/result-dir.sh"

# ── Config file override ─────────────────────────────────────────
# shellcheck disable=SC1091
source "$LIB_DIR/config.sh"
[ "$SEATBELT_CHECKOV_ENABLED" = "false" ] && exit 0
rm -f "$SEATBELT_RESULT_DIR/checkov"
# shellcheck disable=SC1091
source "$LIB_DIR/block-emit.sh"

# ── checkov availability ────────────────────────────────────────────
CHECKOV_CMD=""
if command -v checkov &>/dev/null; then
    CHECKOV_CMD="checkov"
elif python3 -c "import checkov" &>/dev/null 2>&1; then
    CHECKOV_CMD="python3 -m checkov.main"
fi

if [ -z "$CHECKOV_CMD" ]; then
    echo "SEATBELT DEGRADED: checkov not installed — IaC scanning DISABLED (pip3 install checkov | /seatbelt:doctor)" >&2
    exit 0
fi

# ── Extract ALL staged IaC files to temp dir ─────────────────────
# Files are extracted preserving directory structure so multi-file IaC
# configs (Terraform modules, Helm charts, Kustomize) resolve correctly.
SCAN_DIR=$(mktemp -d)
trap 'rm -rf "$SCAN_DIR"' EXIT

# ── Portable timeout (config-driven) ─────────────────────────────
TIMEOUT_CMD=""
if [ -n "${SEATBELT_CHECKOV_TIMEOUT:-}" ]; then
    if command -v timeout &>/dev/null; then
        TIMEOUT_CMD="timeout $SEATBELT_CHECKOV_TIMEOUT"
    elif command -v gtimeout &>/dev/null; then
        TIMEOUT_CMD="gtimeout $SEATBELT_CHECKOV_TIMEOUT"
    fi
fi

EXTRACTED=0
EXPECTED=0
while IFS= read -r -d '' staged_file; do
    [ -z "$staged_file" ] && continue

    case "$staged_file" in
        *Dockerfile*|*dockerfile*)                              ;;
        *.tf|*.tf.json)                                         ;;
        *docker-compose*.yml|*docker-compose*.yaml)             ;;
        .github/workflows/*.yml|.github/workflows/*.yaml)       ;;
        *k8s*/*.yml|*k8s*/*.yaml|*kubernetes*/*.yml|*kubernetes*/*.yaml) ;;
        *helm*/*.yml|*helm*/*.yaml)                             ;;
        *)                                                      continue ;;
    esac

    # Skip symlinks (mode 120000) and submodules (mode 160000)
    local_mode=$(git ls-files -s -- "$staged_file" 2>/dev/null | cut -d' ' -f1)
    if [ "$local_mode" = "120000" ] || [ "$local_mode" = "160000" ]; then continue; fi

    EXPECTED=$((EXPECTED + 1))
    mkdir -p "$SCAN_DIR/$(dirname "$staged_file")" 2>/dev/null || continue
    git show ":$staged_file" > "$SCAN_DIR/$staged_file" 2>/dev/null || continue
    EXTRACTED=$((EXTRACTED + 1))
done < <(git diff -z --cached --name-only --diff-filter=ACMR 2>/dev/null)

[ "$EXPECTED" -eq 0 ] && exit 0

if [ "$EXTRACTED" -lt "$EXPECTED" ]; then
    echo "SEATBELT: checkov: extracted $EXTRACTED/$EXPECTED staged files (some skipped)" >&2
fi

# ── Run checkov on entire directory at once ──────────────────────
SCAN_EXIT=0
if [ -n "$TIMEOUT_CMD" ]; then
    # shellcheck disable=SC2086
    SCAN_OUTPUT=$($TIMEOUT_CMD $CHECKOV_CMD --directory "$SCAN_DIR" --quiet --output json 2>&1) || SCAN_EXIT=$?
else
    SCAN_OUTPUT=$($CHECKOV_CMD --directory "$SCAN_DIR" --quiet --output json 2>&1) || SCAN_EXIT=$?
fi

# Detect timeout (exit 124 from coreutils timeout, 137 from SIGKILL)
if [ "$SCAN_EXIT" -eq 124 ] || [ "$SCAN_EXIT" -eq 137 ]; then
    echo "SEATBELT DEGRADED: checkov timed out after ${SEATBELT_CHECKOV_TIMEOUT:-?}s — scan skipped" >&2
    exit 0
fi

# Parse JSON for findings
FINDING_INFO=$(printf '%s' "$SCAN_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Handle both top-level dict (single dir) and list (multi-framework) shapes
    if isinstance(data, list):
        failed_checks = []
        for item in data:
            if isinstance(item, dict) and 'results' in item:
                fc = item.get('results', {}).get('failed_checks', [])
                if isinstance(fc, list):
                    failed_checks.extend(fc)
    else:
        results = data.get('results', {})
        failed_checks = results.get('failed_checks', [])
    if not isinstance(failed_checks, list):
        failed_checks = []
    count = len(failed_checks)
    summary_lines = []
    for fc in failed_checks[:5]:
        check_id = fc.get('check_id', '')
        resource = fc.get('resource', '')
        file_path = fc.get('file_path', '')
        summary_lines.append(f'  {check_id} on {resource} ({file_path})')
    summary = '; '.join(summary_lines)
    print(f'{count}|{summary}')
except Exception:
    print('-1|')
" 2>/dev/null || echo "-1|")

FINDING_COUNT="${FINDING_INFO%%|*}"
FINDING_SUMMARY="${FINDING_INFO#*|}"
BLOCKED=0
BLOCKED_COUNT=0
BLOCK_DETAILS=""

# Fallback to grep if JSON parse failed
if [ "$FINDING_COUNT" = "-1" ]; then
    FAILED=$(echo "$SCAN_OUTPUT" | grep -c "FAILED" 2>/dev/null || true)
    FAILED=${FAILED:-0}
    PARSE_ERRORS=$(echo "$SCAN_OUTPUT" | grep -cE "Parsing errors:" 2>/dev/null || true)
    PARSE_ERRORS=${PARSE_ERRORS:-0}

    if [ "$FAILED" -gt 0 ]; then
        BLOCKED=1
        BLOCKED_COUNT=$FAILED
        BLOCK_DETAILS="$(echo "$SCAN_OUTPUT" | grep "FAILED" | head -5)\n"
    elif [ "$PARSE_ERRORS" -gt 0 ]; then
        echo "SEATBELT: checkov parse errors in staged IaC files — results may be incomplete" >&2
    fi
else
    if [ "$FINDING_COUNT" -gt 0 ] 2>/dev/null; then
        BLOCKED=1
        BLOCKED_COUNT=$FINDING_COUNT
        BLOCK_DETAILS="${FINDING_SUMMARY}\n"
    fi
fi

# ── Emit results ────────────────────────────────────────────────────
if [ "$BLOCKED" = "1" ]; then
    REASON="IaC MISCONFIGURATION in staged files — commit blocked.

checkov found failed checks:

$(printf '%b' "$BLOCK_DETAILS")

Fix: Address the failed checks listed above.
False positive? Add #checkov:skip=CKV_XXX:reason above the affected line
Bypass once: export SKIP_CHECKOV=1 in your shell, then retry"
    block_emit "checkov" "$REASON"
    # Always write result file so scan-summary can aggregate findings
    mkdir -p "$SEATBELT_RESULT_DIR"
    if [ "${SEATBELT_STRICT:-true}" = "false" ]; then
        echo "${BLOCKED_COUNT} finding(s) (downgraded from block)" >> "$SEATBELT_RESULT_DIR/checkov"
    else
        echo "${BLOCKED_COUNT} finding(s) (blocked)" >> "$SEATBELT_RESULT_DIR/checkov"
    fi
fi

exit 0
