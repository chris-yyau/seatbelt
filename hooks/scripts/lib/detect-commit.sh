#!/usr/bin/env bash
# Shared git-commit detection for seatbelt hooks.
# Usage: source this file AFTER setting HOOK_DATA from stdin.
# Sets IS_GIT_COMMIT="yes" if the hook input is a git commit command, "" otherwise.
# Requires: python3 (falls back to "" if missing)

IS_GIT_COMMIT=""

[ -z "${HOOK_DATA:-}" ] && return 0

# Fast pre-filter: skip if no git commit pattern in raw data
case "$HOOK_DATA" in
    *\"Bash\"*git\ commit*) ;;
    *git\ commit*\"Bash\"*) ;;
    *) return 0 ;;
esac

# python3 JSON parsing
if ! command -v python3 &>/dev/null; then
    return 0  # fail-open without python3
fi

# shellcheck disable=SC2034  # IS_GIT_COMMIT is consumed by the sourcing script
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
