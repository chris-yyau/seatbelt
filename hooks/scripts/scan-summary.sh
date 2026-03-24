#!/usr/bin/env bash
# Seatbelt: aggregate scan summary (PostToolUse hook)
# Collects results written by scanner hooks and emits a single summary line.
# Skip: SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR

[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0

# ── Detect git commit via shared library ─────────────────────
HOOK_DATA=$(cat 2>/dev/null || true)
LIB_DIR="$(cd "$(dirname "$0")" && pwd)/lib"
source "$LIB_DIR/detect-commit.sh"
[ "$IS_GIT_COMMIT" != "yes" ] && exit 0

# ── Compute result directory (repo-specific to avoid cross-repo collisions) ──
source "$LIB_DIR/result-dir.sh"
[ ! -d "$SEATBELT_RESULT_DIR" ] && exit 0

# Sum findings across all result files (each file may have multiple lines
# from scanning multiple lockfiles/workflows — one line per scanned file)
SCANNER_COUNT=0
TOTAL_FINDINGS=0
SUMMARY_PARTS=""

for result_file in "$SEATBELT_RESULT_DIR"/*; do
    [ -f "$result_file" ] || continue
    scanner=$(basename "$result_file")
    scanner_total=0

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        line_count=$(echo "$line" | grep -oE '^[0-9]+' | head -1)
        line_count=${line_count:-0}
        if [ "$line_count" -gt 0 ] 2>/dev/null; then
            scanner_total=$((scanner_total + line_count))
        fi
    done < "$result_file"

    if [ "$scanner_total" -gt 0 ]; then
        SCANNER_COUNT=$((SCANNER_COUNT + 1))
        TOTAL_FINDINGS=$((TOTAL_FINDINGS + scanner_total))
        SUMMARY_PARTS="${SUMMARY_PARTS}${scanner}: ${scanner_total} finding(s); "
    fi
done

# ── Emit summary ─────────────────────────────────────────────
if [ "$SCANNER_COUNT" -gt 0 ]; then
    echo "SEATBELT SUMMARY: ${TOTAL_FINDINGS} finding(s) from ${SCANNER_COUNT} scanner(s) — ${SUMMARY_PARTS%%; }" >&2
fi

# ── Cleanup ──────────────────────────────────────────────────
rm -rf "$SEATBELT_RESULT_DIR"

exit 0
