#!/usr/bin/env bash
# Seatbelt: validate commit message follows conventional commits format
# Scanner: commitlint | Fail mode: warn only (advisory, never blocks)
# Skip: SKIP_COMMITLINT=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
# shellcheck disable=SC1091
source "$(cd "$(dirname "$0")" && pwd)/lib/skip-audit.sh" || true
[ "${SKIP_SEATBELT:-0}" = "1" ] && { seatbelt_log_skip "commitlint" "SKIP_SEATBELT"; exit 0; }
[ "${SKIP_COMMITLINT:-0}" = "1" ] && { seatbelt_log_skip "commitlint" "SKIP_COMMITLINT"; exit 0; }

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
[ "$SEATBELT_COMMITLINT_ENABLED" = "false" ] && exit 0

# ── Portable timeout (config-driven) ─────────────────────────────
TIMEOUT_CMD=""
if [ -n "${SEATBELT_COMMITLINT_TIMEOUT:-}" ]; then
    if command -v timeout &>/dev/null; then
        TIMEOUT_CMD="timeout $SEATBELT_COMMITLINT_TIMEOUT"
    elif command -v gtimeout &>/dev/null; then
        TIMEOUT_CMD="gtimeout $SEATBELT_COMMITLINT_TIMEOUT"
    fi
fi

# ── Extract commit message from HOOK_DATA ─────────────────────────
# Parse the git commit command to find -m/--message argument
# shellcheck disable=SC2086
COMMIT_MSG=$(printf '%s' "$HOOK_DATA" | SEATBELT_LIB_DIR="$LIB_DIR" ${TIMEOUT_CMD:+$TIMEOUT_CMD} python3 -I -c "
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
        # --fixup, --squash, -F/--file take a message from elsewhere → skip validation
        skip = False
        for t in args:
            if t in ('--fixup', '--squash', '--file', '-F'):
                skip = True
            elif t.startswith('--file=') or t.startswith('--fixup=') or t.startswith('--squash='):
                skip = True
            elif len(t) > 2 and t[:2] == '-F' and not t[2:].startswith('-'):
                skip = True
            if skip:
                break
        if not skip:
            # Find -m or --message (last one wins, matching git behavior)
            msgs = []
            i = 0
            while i < len(args):
                if args[i] in ('-m', '--message') and i + 1 < len(args):
                    msgs.append(args[i + 1])
                    i += 2
                elif args[i].startswith('-m') and len(args[i]) > 2:
                    msgs.append(args[i][2:])
                    i += 1
                elif args[i].startswith('--message='):
                    msgs.append(args[i][10:])
                    i += 1
                else:
                    i += 1
            if msgs:
                print(msgs[-1])
except Exception:
    pass
" 2>/dev/null || true)

# No message found (interactive commit, --amend without -m, -F, --fixup, etc.) → skip
[ -z "$COMMIT_MSG" ] && exit 0

# ── Validate against conventional commits ─────────────────────────
# Accept: type(scope)!: description
# Accept: Merge ..., Revert "..."
VALID=0
if printf '%s' "$COMMIT_MSG" | grep -qE '^(feat|fix|refactor|docs|test|chore|perf|ci|build|style|revert)(\(.+\))?!?: .+'; then
    VALID=1
elif printf '%s' "$COMMIT_MSG" | grep -qE '^Merge '; then
    VALID=1
elif printf '%s' "$COMMIT_MSG" | grep -qE '^Revert "'; then
    VALID=1
fi

if [ "$VALID" -eq 0 ]; then
    echo "SEATBELT: commit message does not follow conventional commits format" >&2
    echo "  Expected: type[(scope)]: description  (scope is optional)" >&2
    echo "  Types: feat, fix, refactor, docs, test, chore, perf, ci, build, style, revert" >&2
    echo "  Got: $(printf '%s' "$COMMIT_MSG" | head -c 80)" >&2
fi

exit 0
