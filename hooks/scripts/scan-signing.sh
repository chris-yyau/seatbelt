#!/usr/bin/env bash
# Seatbelt: advisory — remind to enable commit signing
# Scanner: signing | Fail mode: warn only (advisory nudge, never blocks)
# Skip: SKIP_SIGNING=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_SIGNING:-0}" = "1" ] && exit 0

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

# ── Check if commit is already being signed ───────────────────────
# Check 1: Is -S or --gpg-sign in the commit command?
CMD_HAS_SIGN=$(printf '%s' "$HOOK_DATA" | python3 -c "
import sys, json, re, shlex
try:
    d = json.load(sys.stdin)
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
        while tokens and re.match(r'^\w+=', tokens[0]):
            tokens = tokens[1:]
        if len(tokens) >= 2 and tokens[0] == 'git' and tokens[1] == 'commit':
            for t in tokens[2:]:
                if t in ('-S', '--gpg-sign') or t.startswith('--gpg-sign='):
                    print('yes')
                    break
            break
except Exception:
    pass
" 2>/dev/null || true)

[ "$CMD_HAS_SIGN" = "yes" ] && exit 0

# Check 2: Is commit.gpgsign enabled in git config?
GPGSIGN=$(git config --get commit.gpgsign 2>/dev/null || true)
[ "$GPGSIGN" = "true" ] && exit 0

# ── Emit advisory ────────────────────────────────────────────────
echo "SEATBELT: commit signing not enabled — consider: git config --global commit.gpgsign true" >&2

exit 0
