#!/usr/bin/env bash
# Seatbelt: scan staged lock files for dependency CVEs before git commit
# Scanner: trivy | Fail mode: warn only (never blocks)
# Skip: SKIP_TRIVY=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_TRIVY:-0}" = "1" ] && exit 0

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

# ── trivy availability ──────────────────────────────────────────────
if ! command -v trivy &>/dev/null; then
    echo "SEATBELT DEGRADED: trivy not installed — dependency CVE scanning DISABLED (brew install trivy | /seatbelt doctor)" >&2
    exit 0
fi

# ── Collect staged lock files ───────────────────────────────────────
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
[ -z "$STAGED_FILES" ] && exit 0

LOCKFILES=$(echo "$STAGED_FILES" | grep -E '(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|requirements\.txt|poetry\.lock|uv\.lock|Pipfile\.lock|go\.sum|Gemfile\.lock|composer\.lock)$' || true)
[ -z "$LOCKFILES" ] && exit 0

# ── Check trivy DB cache ───────────────────────────────────────────
TRIVY_CACHE="${TRIVY_CACHE_DIR:-}"
if [ -z "$TRIVY_CACHE" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        TRIVY_CACHE="${HOME}/Library/Caches/trivy/db"
    else
        TRIVY_CACHE="${HOME}/.cache/trivy/db"
    fi
else
    TRIVY_CACHE="${TRIVY_CACHE}/db"
fi

if [ ! -d "$TRIVY_CACHE" ] || [ -z "$(ls -A "$TRIVY_CACHE" 2>/dev/null)" ]; then
    echo "SEATBELT: trivy: no vulnerability DB cached — run 'trivy image --download-db-only' to enable dep scanning" >&2
    exit 0
fi

# ── Portable timeout ───────────────────────────────────────────────
TIMEOUT_CMD=""
if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout 30"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout 30"
fi

# ── Scan lock files (warn only — never blocks) ─────────────────────
while IFS= read -r lf; do
    [ -f "$lf" ] || continue
    OUTPUT=$($TIMEOUT_CMD trivy fs --scanners vuln --severity HIGH,CRITICAL --skip-db-update --no-progress "$lf" 2>/dev/null) || true
    HAS_VULNS=$(echo "$OUTPUT" | grep -E "Total: [1-9]" 2>/dev/null || true)
    if [ -n "$HAS_VULNS" ]; then
        echo "SEATBELT: trivy found vulnerabilities in $(basename "$lf"):" >&2
        echo "$OUTPUT" | grep -E "(HIGH|CRITICAL)" | head -5 >&2
    fi
done <<< "$LOCKFILES"

exit 0
