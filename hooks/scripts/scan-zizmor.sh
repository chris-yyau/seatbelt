#!/usr/bin/env bash
# Seatbelt: scan staged GitHub Actions workflows for security issues before git commit
# Scanner: zizmor | Fail mode: warn only (never blocks)
# Skip: SKIP_ZIZMOR=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_ZIZMOR:-0}" = "1" ] && exit 0

# ── Detect git commit via shared library ─────────────────────────
# shellcheck disable=SC2034  # HOOK_DATA is consumed by sourced detect-commit.sh
HOOK_DATA=$(cat 2>/dev/null || true)
LIB_DIR="$(cd "$(dirname "$0")" && pwd)/lib"
# shellcheck disable=SC1091
source "$LIB_DIR/detect-commit.sh"
[ "$IS_GIT_COMMIT" != "yes" ] && exit 0
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# ── zizmor availability ─────────────────────────────────────────────
if ! command -v zizmor &>/dev/null; then
    echo "SEATBELT DEGRADED: zizmor not installed — GitHub Actions scanning DISABLED (pip3 install zizmor | /seatbelt doctor)" >&2
    exit 0
fi

# ── Extract staged workflow files to temp dir ─────────────────────
SCAN_DIR=$(mktemp -d)
trap 'rm -rf "$SCAN_DIR"' EXIT

EXTRACTED=0
EXPECTED=0
while IFS= read -r -d '' wf; do
    [ -z "$wf" ] && continue

    case "$wf" in
        .github/workflows/*.yml|.github/workflows/*.yaml) ;;
        *)                                                 continue ;;
    esac

    local_mode=$(git ls-files -s -- "$wf" 2>/dev/null | cut -d' ' -f1)
    if [ "$local_mode" = "120000" ] || [ "$local_mode" = "160000" ]; then continue; fi

    EXPECTED=$((EXPECTED + 1))
    mkdir -p "$SCAN_DIR/$(dirname "$wf")" 2>/dev/null || continue
    git show ":$wf" > "$SCAN_DIR/$wf" 2>/dev/null || continue
    EXTRACTED=$((EXTRACTED + 1))

    SCAN_OUTPUT=$(zizmor --no-progress --format json "$SCAN_DIR/$wf" 2>&1) || true

    # Parse JSON for findings
    # zizmor v1 JSON schema: top-level array with ident, determinations.severity,
    # and locations[].symbolic.key.Local.given_path
    FINDING_INFO=$(printf '%s' "$SCAN_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # zizmor outputs a top-level array of findings
    if not isinstance(data, list):
        print('-1|')
        sys.exit(0)
    count = len(data)
    summary_lines = []
    for f in data[:5]:
        ident = f.get('ident', f.get('rule', ''))
        det = f.get('determinations', {})
        severity = det.get('severity', f.get('severity', '')) if isinstance(det, dict) else ''
        file_path = ''
        locs = f.get('locations', [])
        if locs:
            sym = locs[0].get('symbolic', {})
            key = sym.get('key', {})
            local = key.get('Local', {}) if isinstance(key, dict) else {}
            file_path = local.get('given_path', '') if isinstance(local, dict) else ''
        summary_lines.append(f'  {ident} [{severity}] {file_path}')
    summary = '; '.join(summary_lines)
    print(f'{count}|{summary}')
except Exception:
    print('-1|')
" 2>/dev/null || echo "-1|")

    FINDING_COUNT="${FINDING_INFO%%|*}"
    FINDING_SUMMARY="${FINDING_INFO#*|}"

    # Fallback to grep if JSON parse failed (handles older zizmor that ignores --format json)
    if [ "$FINDING_COUNT" = "-1" ]; then
        if echo "$SCAN_OUTPUT" | grep -qE '(warning|error)\['; then
            HITS=$(echo "$SCAN_OUTPUT" | grep -cE '(warning|error)\[' 2>/dev/null || echo "0")
            echo "SEATBELT: zizmor found ${HITS} issue(s) in $(basename "$wf"):" >&2
            echo "$SCAN_OUTPUT" | grep -E '(warning|error)\[' | head -3 >&2
            # Write result for summary aggregation (append: multiple workflows may have findings)
            # shellcheck disable=SC1091
            source "$LIB_DIR/result-dir.sh"
            mkdir -p "$SEATBELT_RESULT_DIR"
            echo "${HITS} issue(s) in $(basename "$wf")" >> "$SEATBELT_RESULT_DIR/zizmor"
        elif [ -n "$SCAN_OUTPUT" ]; then
            # Non-empty output that is neither JSON nor text findings — likely a CLI error
            # (e.g. --format json unsupported). Emit a degraded warning rather than silently skip.
            echo "SEATBELT: zizmor: could not parse scan output for $(basename "$wf") — scan result unknown" >&2
        fi
    else
        if [ "$FINDING_COUNT" -gt 0 ] 2>/dev/null; then
            echo "SEATBELT: zizmor found ${FINDING_COUNT} issue(s) in $(basename "$wf"):" >&2
            if [ -n "$FINDING_SUMMARY" ]; then
                printf '%s\n' "$FINDING_SUMMARY" >&2
            fi
            # Write result for summary aggregation (append: multiple workflows may have findings)
            # shellcheck disable=SC1091
            source "$LIB_DIR/result-dir.sh"
            mkdir -p "$SEATBELT_RESULT_DIR"
            echo "${FINDING_COUNT} issue(s) in $(basename "$wf")" >> "$SEATBELT_RESULT_DIR/zizmor"
        fi
    fi
done < <(git diff -z --cached --name-only --diff-filter=ACMR 2>/dev/null)

[ "$EXPECTED" -eq 0 ] && exit 0

if [ "$EXTRACTED" -lt "$EXPECTED" ]; then
    echo "SEATBELT: zizmor: extracted $EXTRACTED/$EXPECTED staged files (some skipped)" >&2
fi

exit 0
