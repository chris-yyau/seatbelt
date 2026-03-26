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
    echo "SEATBELT DEGRADED: checkov not installed — IaC scanning DISABLED (pip3 install checkov | /seatbelt doctor)" >&2
    exit 0
fi

# ── Extract staged IaC files to temp dir ──────────────────────────
# Each staged file is extracted individually via `git show ":path"`.
# Known limitation: multi-file IaC configs (e.g. Terraform modules with
# relative `source` paths) that span multiple staged files may produce
# parse errors in checkov because neighbour files are absent from SCAN_DIR.
# Those files are skipped (fail-open) with a SEATBELT warning on stderr.
SCAN_DIR=$(mktemp -d)
trap 'rm -rf "$SCAN_DIR"' EXIT

BLOCKED=0
BLOCK_DETAILS=""
EXTRACTED=0
EXPECTED=0
while IFS= read -r -d '' staged_file; do
    [ -z "$staged_file" ] && continue

    FRAMEWORK=""
    case "$staged_file" in
        *Dockerfile*|*dockerfile*)                              FRAMEWORK="dockerfile" ;;
        *.tf|*.tf.json)                                         FRAMEWORK="terraform" ;;
        *docker-compose*.yml|*docker-compose*.yaml)             FRAMEWORK="docker_compose" ;;
        .github/workflows/*.yml|.github/workflows/*.yaml)       FRAMEWORK="github_actions" ;;
        *k8s*/*.yml|*k8s*/*.yaml|*kubernetes*/*.yml|*kubernetes*/*.yaml) FRAMEWORK="kubernetes" ;;
        *helm*/*.yml|*helm*/*.yaml)                             FRAMEWORK="helm" ;;
        *)                                                      continue ;;
    esac

    # Skip symlinks (mode 120000) and submodules (mode 160000)
    local_mode=$(git ls-files -s -- "$staged_file" 2>/dev/null | cut -d' ' -f1)
    if [ "$local_mode" = "120000" ] || [ "$local_mode" = "160000" ]; then continue; fi

    EXPECTED=$((EXPECTED + 1))
    mkdir -p "$SCAN_DIR/$(dirname "$staged_file")" 2>/dev/null || continue
    git show ":$staged_file" > "$SCAN_DIR/$staged_file" 2>/dev/null || continue
    EXTRACTED=$((EXTRACTED + 1))

    SCAN_OUTPUT=$($CHECKOV_CMD --file "$SCAN_DIR/$staged_file" --framework "$FRAMEWORK" --quiet --output json 2>&1) || true

    # Parse JSON for findings
    FINDING_INFO=$(printf '%s' "$SCAN_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Handle both top-level dict (single file) and list (multi-file) shapes
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

    # Fallback to grep if JSON parse failed
    if [ "$FINDING_COUNT" = "-1" ]; then
        FAILED=$(echo "$SCAN_OUTPUT" | grep -c "FAILED" 2>/dev/null || true)
        FAILED=${FAILED:-0}
        PARSE_ERRORS=$(echo "$SCAN_OUTPUT" | grep -cE "Parsing errors:" 2>/dev/null || true)
        PARSE_ERRORS=${PARSE_ERRORS:-0}

        if [ "$FAILED" -gt 0 ]; then
            BLOCKED=1
            BLOCK_DETAILS="${BLOCK_DETAILS}$(echo "$SCAN_OUTPUT" | grep "FAILED" | head -3)\n"
        elif [ "$PARSE_ERRORS" -gt 0 ]; then
            echo "SEATBELT: checkov parse error in $(basename "$staged_file") — skipping" >&2
        fi
    else
        if [ "$FINDING_COUNT" -gt 0 ] 2>/dev/null; then
            BLOCKED=1
            BLOCK_DETAILS="${BLOCK_DETAILS}${FINDING_SUMMARY}\n"
        fi
    fi
done < <(git diff -z --cached --name-only --diff-filter=ACMR 2>/dev/null)

[ "$EXPECTED" -eq 0 ] && exit 0

if [ "$EXTRACTED" -lt "$EXPECTED" ]; then
    echo "SEATBELT: checkov: extracted $EXTRACTED/$EXPECTED staged files (some skipped)" >&2
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
fi

exit 0
