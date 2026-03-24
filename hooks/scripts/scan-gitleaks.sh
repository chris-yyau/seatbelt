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

# ── Detect git commit via shared library ─────────────────────────
# shellcheck disable=SC2034  # HOOK_DATA is consumed by sourced detect-commit.sh
HOOK_DATA=$(cat 2>/dev/null || true)
LIB_DIR="$(cd "$(dirname "$0")" && pwd)/lib"
# shellcheck disable=SC1091  # dynamically resolved path
source "$LIB_DIR/detect-commit.sh"
[ "$IS_GIT_COMMIT" != "yes" ] && exit 0

# Not in a git repo → skip
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# ── Clean stale scan results from previous blocked commits ────────
# shellcheck disable=SC1091
source "$LIB_DIR/result-dir.sh"
rm -rf "$SEATBELT_RESULT_DIR"

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
