#!/usr/bin/env bash
# Seatbelt: validate commit message follows conventional commits format
# Scanner: commitlint | Fail mode: warn only (advisory, never blocks)
# Skip: SKIP_COMMITLINT=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_COMMITLINT:-0}" = "1" ] && exit 0

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
# commitlint is not in the standard config.sh scanner list, so we handle
# the env var directly with a default of "true" (enabled).
SEATBELT_COMMITLINT_ENABLED="${SEATBELT_COMMITLINT_ENABLED:-true}"
[ "$SEATBELT_COMMITLINT_ENABLED" = "false" ] && exit 0

# ── Extract commit message from HOOK_DATA ─────────────────────────
# Parse the git commit command to find -m/--message argument
COMMIT_MSG=$(printf '%s' "$HOOK_DATA" | python3 -c "
import sys, json, re, shlex
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', d.get('toolInput', {}))
    if isinstance(inp, str):
        inp = json.loads(inp)
    cmd = inp.get('command', '')
    # Find the git commit segment
    for seg in re.split(r'&&|\|\||[;\n|]', cmd):
        seg = seg.strip()
        if not seg:
            continue
        try:
            tokens = shlex.split(seg)
        except ValueError:
            tokens = shlex.split(seg, posix=False)
        # Skip env var prefixes
        while tokens and re.match(r'^\w+=', tokens[0]):
            tokens = tokens[1:]
        if len(tokens) >= 2 and tokens[0] == 'git' and tokens[1] == 'commit':
            # Check for --fixup, --squash, -F/--file (skip validation)
            for t in tokens[2:]:
                if t in ('--fixup', '--squash', '-F', '--file'):
                    sys.exit(0)
            # Find -m or --message
            msgs = []
            i = 2
            while i < len(tokens):
                if tokens[i] in ('-m', '--message') and i + 1 < len(tokens):
                    msgs.append(tokens[i + 1])
                    i += 2
                elif tokens[i].startswith('-m') and len(tokens[i]) > 2:
                    msgs.append(tokens[i][2:])
                    i += 1
                elif tokens[i].startswith('--message='):
                    msgs.append(tokens[i][10:])
                    i += 1
                else:
                    i += 1
            if msgs:
                # Use first -m message for validation
                print(msgs[0])
            break
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
    echo "  Expected: type(scope): description" >&2
    echo "  Types: feat, fix, refactor, docs, test, chore, perf, ci, build, style, revert" >&2
    echo "  Got: $(printf '%s' "$COMMIT_MSG" | head -c 80)" >&2
fi

exit 0
