#!/usr/bin/env bash
# Seatbelt: scan staged GitHub Actions workflows for security issues before git commit
# Scanner: zizmor | Fail mode: warn only (never blocks)
# Skip: SKIP_ZIZMOR=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_ZIZMOR:-0}" = "1" ] && exit 0

# ── Consume stdin ───────────────────────────────────────────────────
HOOK_DATA=$(cat 2>/dev/null || true)
[ -z "$HOOK_DATA" ] && exit 0

# ── Fast pre-filter ─────────────────────────────────────────────────
case "$HOOK_DATA" in
    *\"Bash\"*git\ commit*) ;;
    *git\ commit*\"Bash\"*) ;;
    *) exit 0 ;;
esac

# ── python3 JSON parsing ───────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    exit 0
fi

IS_GIT_COMMIT=$(printf '%s' "$HOOK_DATA" | python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
    tool = d.get('tool_name', d.get('toolName', ''))
    if tool != 'Bash':
        sys.exit(0)
    inp = d.get('tool_input', d.get('toolInput', {}))
    if isinstance(inp, str):
        inp = json.loads(inp)
    cmd = inp.get('command', '')
    for seg in re.split(r'&&|\|\||[;\n|]', cmd):
        seg = seg.strip()
        while re.match(r'^\w+=\S*\s', seg):
            seg = re.sub(r'^\w+=\S*\s+', '', seg, count=1)
        if re.match(r'git\s+commit\b', seg):
            print('yes')
            break
except Exception:
    pass
" 2>/dev/null || true)

[ "$IS_GIT_COMMIT" != "yes" ] && exit 0
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# ── zizmor availability ─────────────────────────────────────────────
if ! command -v zizmor &>/dev/null; then
    echo "SEATBELT DEGRADED: zizmor not installed — GitHub Actions scanning DISABLED (pip3 install zizmor | /seatbelt doctor)" >&2
    exit 0
fi

# ── Collect staged workflow files ───────────────────────────────────
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
[ -z "$STAGED_FILES" ] && exit 0

WORKFLOW_FILES=$(echo "$STAGED_FILES" | grep -E '\.github/workflows/.*\.(yml|yaml)$' || true)
[ -z "$WORKFLOW_FILES" ] && exit 0

# ── Scan workflow files (warn only — never blocks) ──────────────────
while IFS= read -r wf; do
    [ -f "$wf" ] || continue
    OUTPUT=$(zizmor --no-progress "$wf" 2>&1) || true
    if echo "$OUTPUT" | grep -qE '(warning|error)\['; then
        HITS=$(echo "$OUTPUT" | grep -cE '(warning|error)\[' 2>/dev/null || echo "0")
        echo "SEATBELT: zizmor found ${HITS} issue(s) in $(basename "$wf"):" >&2
        echo "$OUTPUT" | grep -E '(warning|error)\[' | head -3 >&2
    fi
done <<< "$WORKFLOW_FILES"

exit 0
