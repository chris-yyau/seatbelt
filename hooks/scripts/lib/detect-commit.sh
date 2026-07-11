#!/usr/bin/env bash
# Shared git-commit detection for seatbelt hooks.
# Usage: source this file AFTER setting HOOK_DATA from stdin.
# Sets IS_GIT_COMMIT="yes" if the hook input is a git commit command, "" otherwise.
# Requires: python3 (falls back to "" if missing)

IS_GIT_COMMIT=""

[ -z "${HOOK_DATA:-}" ] && return 0

# Fast pre-filter: skip if no plausible git…commit pattern in raw data.
# Uses git*commit (not the literal "git commit") so option-prefixed forms
# like `git -c x=y commit` / `git -C dir commit` still reach the parser;
# the python below makes the precise decision.
case "$HOOK_DATA" in
    *\"Bash\"*git*commit*) ;;
    *git*commit*\"Bash\"*) ;;
    *) return 0 ;;
esac

# python3 JSON parsing
if ! command -v python3 &>/dev/null; then
    return 0  # fail-open without python3
fi

# Resolve this lib's own directory so the inline python can import the
# shared parser regardless of how the caller sourced us.
_seatbelt_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd 2>/dev/null)" || _seatbelt_lib_dir=""

# shellcheck disable=SC2034  # IS_GIT_COMMIT is consumed by the sourcing script
IS_GIT_COMMIT=$(printf '%s' "$HOOK_DATA" | SEATBELT_LIB_DIR="$_seatbelt_lib_dir" python3 -I -c "
import os, sys, json
# python3 runs with -I (isolated): cwd is NOT on sys.path, so a repo-supplied
# json.py / sitecustomize.py / git_commit_parse.py cannot hijack these imports.
_lib = os.environ.get('SEATBELT_LIB_DIR', '')
if _lib:
    sys.path.insert(0, _lib)
try:
    from git_commit_parse import commit_args
    d = json.load(sys.stdin)
    tool = d.get('tool_name', d.get('toolName', ''))
    if tool != 'Bash':
        sys.exit(0)
    inp = d.get('tool_input', d.get('toolInput', {}))
    if isinstance(inp, str):
        inp = json.loads(inp)
    if commit_args(inp.get('command', '')) is not None:
        print('yes')
except Exception:
    pass
" 2>/dev/null || true)
unset _seatbelt_lib_dir
