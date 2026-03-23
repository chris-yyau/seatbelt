#!/usr/bin/env bash
# Seatbelt: scan staged changes for secrets before git commit
# Scanner: gitleaks | Fail mode: BLOCK on findings, fail-open on errors
# Skip: SKIP_GITLEAKS=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Block emission helper ────────────────────────────────────────────
block_emit() {
    local reason="$1"
    if command -v jq &>/dev/null; then
        jq -n --arg r "$reason" '{"decision":"block","reason":$r}'
    else
        local escaped
        escaped=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | head -c 2000)
        printf '{"decision":"block","reason":"%s"}\n' "$escaped"
    fi
}

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_GITLEAKS:-0}" = "1" ] && exit 0

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
    exit 0  # fail-open without python3
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

# Not in a git repo → skip
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# ── gitleaks availability ───────────────────────────────────────────
if ! command -v gitleaks &>/dev/null; then
    echo "SEATBELT DEGRADED: gitleaks not installed — secret scanning DISABLED (brew install gitleaks | /seatbelt doctor)" >&2
    exit 0
fi

# ── Run gitleaks ────────────────────────────────────────────────────
GITLEAKS_EXIT=0
GITLEAKS_OUTPUT=$(gitleaks protect --staged --no-banner 2>&1) || GITLEAKS_EXIT=$?

# Exit 0 = clean
[ "$GITLEAKS_EXIT" -eq 0 ] && exit 0

# Exit 1 = findings → BLOCK
if [ "$GITLEAKS_EXIT" -eq 1 ]; then
    TRUNCATED=$(echo "$GITLEAKS_OUTPUT" | head -20)
    REASON="SECRET DETECTED in staged changes — commit blocked.

Gitleaks found potential secrets/credentials:

${TRUNCATED}

Fix: Remove the secret from staged files. Use environment variables or a secret manager.
False positive? Add the fingerprint to .gitleaksignore
Bypass once: export SKIP_GITLEAKS=1 in your shell, then retry"
    block_emit "$REASON"
    exit 0
fi

# Other exit codes = tool error → pass through (fail-open)
exit 0
