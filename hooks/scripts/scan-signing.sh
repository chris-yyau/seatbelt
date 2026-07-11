#!/usr/bin/env bash
# Seatbelt: advisory — remind to enable commit signing
# Scanner: signing | Fail mode: warn only (advisory nudge, never blocks)
# Skip: SKIP_SIGNING=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")" && pwd)/lib/skip-audit.sh" || true
[ "${SKIP_SEATBELT:-0}" = "1" ] && { seatbelt_log_skip "signing" "SKIP_SEATBELT"; exit 0; }
[ "${SKIP_SIGNING:-0}" = "1" ] && { seatbelt_log_skip "signing" "SKIP_SIGNING"; exit 0; }

# ── Detect git commit via shared library ─────────────────────────
# shellcheck disable=SC2034  # HOOK_DATA is consumed by sourced detect-commit.sh
HOOK_DATA=$(cat 2>/dev/null || true)
LIB_DIR="$(cd "$(dirname "$0")" && pwd)/lib"
# shellcheck disable=SC1091
if ! source "$LIB_DIR/detect-commit.sh"; then
    exit 0
fi
[ "$IS_GIT_COMMIT" != "yes" ] && exit 0
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# ── Config file override ─────────────────────────────────────────
# shellcheck disable=SC1091
source "$LIB_DIR/config.sh"
[ "$SEATBELT_SIGNING_ENABLED" = "false" ] && exit 0

# ── Portable timeout (config-driven) ─────────────────────────────
TIMEOUT_CMD=""
if [ -n "${SEATBELT_SIGNING_TIMEOUT:-}" ]; then
    if command -v timeout &>/dev/null; then
        TIMEOUT_CMD="timeout $SEATBELT_SIGNING_TIMEOUT"
    elif command -v gtimeout &>/dev/null; then
        TIMEOUT_CMD="gtimeout $SEATBELT_SIGNING_TIMEOUT"
    fi
fi

# ── Check if commit is already being signed ───────────────────────
# Check 1: Is -S or --gpg-sign in the commit command?
# shellcheck disable=SC2086
CMD_HAS_SIGN=$(printf '%s' "$HOOK_DATA" | SEATBELT_LIB_DIR="$LIB_DIR" ${TIMEOUT_CMD:+$TIMEOUT_CMD} python3 -I -c "
import os, sys, json
# python3 runs with -I (isolated): cwd is NOT on sys.path, so a repo-supplied
# json.py / sitecustomize.py / git_commit_parse.py cannot hijack these imports.
_lib = os.environ.get('SEATBELT_LIB_DIR', '')
if _lib:
    sys.path.insert(0, _lib)
try:
    from git_commit_parse import commit_args
    d = json.load(sys.stdin)
    inp = d.get('tool_input', d.get('toolInput', {}))
    if isinstance(inp, str):
        inp = json.loads(inp)
    args = commit_args(inp.get('command', ''))
    if args is not None:
        for t in args:
            if t in ('-S', '--gpg-sign') or t.startswith('--gpg-sign=') or (t.startswith('-S') and len(t) > 2 and t[2] != '-'):
                print('yes')
                break
except Exception:
    pass
" 2>/dev/null || true)

[ "$CMD_HAS_SIGN" = "yes" ] && exit 0

# Check 2: Is commit.gpgsign enabled in git config?
# Git booleans can be true/yes/on/1
_gpgsign=$(git config --get commit.gpgsign 2>/dev/null || true)
case "$_gpgsign" in
    true|yes|on|1) exit 0 ;;
esac

# ── Emit advisory ────────────────────────────────────────────────
echo "SEATBELT: commit signing not enabled — consider: git config --global commit.gpgsign true" >&2

exit 0
