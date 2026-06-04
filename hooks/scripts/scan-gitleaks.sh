#!/usr/bin/env bash
# Seatbelt: scan staged changes for secrets before git commit
# Scanner: gitleaks | Fail mode: BLOCK on findings, fail-open on errors
# Skip: SKIP_GITLEAKS=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")" && pwd)/lib/skip-audit.sh" || true
[ "${SKIP_SEATBELT:-0}" = "1" ] && { seatbelt_log_skip "gitleaks" "SKIP_SEATBELT"; exit 0; }
[ "${SKIP_GITLEAKS:-0}" = "1" ] && { seatbelt_log_skip "gitleaks" "SKIP_GITLEAKS"; exit 0; }

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
# Each scanner cleans its own result file. The summary hook cleans the dir.
rm -f "$SEATBELT_RESULT_DIR/gitleaks"

# ── Config file override ─────────────────────────────────────────
# shellcheck disable=SC1091
source "$LIB_DIR/config.sh"
[ "$SEATBELT_GITLEAKS_ENABLED" = "false" ] && exit 0
# shellcheck disable=SC1091
source "$LIB_DIR/block-emit.sh"

# ── gitleaks availability ───────────────────────────────────────────
if ! command -v gitleaks &>/dev/null; then
    echo "SEATBELT DEGRADED: gitleaks not installed — secret scanning DISABLED (brew install gitleaks | /seatbelt:setup)" >&2
    exit 0
fi

# ── Portable timeout (config-driven, no default for gitleaks) ─────
TIMEOUT_CMD=""
if [ -n "${SEATBELT_GITLEAKS_TIMEOUT:-}" ]; then
    if command -v timeout &>/dev/null; then
        TIMEOUT_CMD="timeout $SEATBELT_GITLEAKS_TIMEOUT"
    elif command -v gtimeout &>/dev/null; then
        TIMEOUT_CMD="gtimeout $SEATBELT_GITLEAKS_TIMEOUT"
    fi
fi

# ── Run gitleaks ────────────────────────────────────────────────────
GITLEAKS_EXIT=0
if [ -n "$TIMEOUT_CMD" ]; then
    GITLEAKS_OUTPUT=$($TIMEOUT_CMD gitleaks protect --staged --no-banner 2>&1) || GITLEAKS_EXIT=$?
else
    GITLEAKS_OUTPUT=$(gitleaks protect --staged --no-banner 2>&1) || GITLEAKS_EXIT=$?
fi

# Exit 0 = clean
[ "$GITLEAKS_EXIT" -eq 0 ] && exit 0

# Timeout (exit 124 from coreutils timeout, 137 from SIGKILL)
if [ "$GITLEAKS_EXIT" -eq 124 ] || [ "$GITLEAKS_EXIT" -eq 137 ]; then
    echo "SEATBELT DEGRADED: gitleaks timed out after ${SEATBELT_GITLEAKS_TIMEOUT:-?}s — scan skipped" >&2
    exit 0
fi

# Exit 1 = findings → BLOCK
if [ "$GITLEAKS_EXIT" -eq 1 ]; then
    TRUNCATED=$(echo "$GITLEAKS_OUTPUT" | head -20)
    REASON="SECRET DETECTED in staged changes — commit blocked.

Gitleaks found potential secrets/credentials:

${TRUNCATED}

Fix: Remove the secret from staged files. Use environment variables or a secret manager.
False positive? Add the fingerprint to .gitleaksignore
Bypass once: export SKIP_GITLEAKS=1 in your shell, then retry"
    block_emit "gitleaks" "$REASON"
    # Always write result file so scan-summary can aggregate findings
    mkdir -p "$SEATBELT_RESULT_DIR"
    if [ "${SEATBELT_STRICT:-true}" = "false" ]; then
        echo "1 finding(s) (downgraded from block)" >> "$SEATBELT_RESULT_DIR/gitleaks"
    else
        echo "1 finding(s) (blocked)" >> "$SEATBELT_RESULT_DIR/gitleaks"
    fi
    exit 0
fi

# Other exit codes = tool error → pass through (fail-open)
exit 0
