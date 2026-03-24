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
import sys, json, re, shlex
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
        if not seg:
            continue
        try:
            tokens = shlex.split(seg)
        except ValueError:
            tokens = shlex.split(seg, posix=False)
        # Skip leading KEY=VALUE tokens
        while tokens and re.match(r'^\w+=', tokens[0]):
            tokens = tokens[1:]
        if len(tokens) >= 2 and tokens[0] == 'git' and tokens[1] == 'commit':
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

    OUTPUT=$(zizmor --no-progress "$SCAN_DIR/$wf" 2>&1) || true
    if echo "$OUTPUT" | grep -qE '(warning|error)\['; then
        HITS=$(echo "$OUTPUT" | grep -cE '(warning|error)\[' 2>/dev/null || echo "0")
        echo "SEATBELT: zizmor found ${HITS} issue(s) in $(basename "$wf"):" >&2
        echo "$OUTPUT" | grep -E '(warning|error)\[' | head -3 >&2
    fi
done < <(git diff -z --cached --name-only --diff-filter=ACMR 2>/dev/null)

[ "$EXPECTED" -eq 0 ] && exit 0

if [ "$EXTRACTED" -lt "$EXPECTED" ]; then
    echo "SEATBELT: zizmor: extracted $EXTRACTED/$EXPECTED staged files (some skipped)" >&2
fi

exit 0
