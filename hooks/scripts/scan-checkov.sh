#!/usr/bin/env bash
# Seatbelt: scan staged IaC files for misconfigurations before git commit
# Scanner: checkov | Fail mode: BLOCK on findings, fail-open on errors
# Skip: SKIP_CHECKOV=1 or SKIP_SEATBELT=1

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
[ "${SKIP_CHECKOV:-0}" = "1" ] && exit 0

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

# ── checkov availability ────────────────────────────────────────────
CHECKOV_CMD=""
if command -v checkov &>/dev/null; then
    CHECKOV_CMD="checkov"
elif python3 -c "import checkov" &>/dev/null 2>&1; then
    CHECKOV_CMD="python3 -m checkov.main"
fi

if [ -z "$CHECKOV_CMD" ]; then
    echo "SEATBELT DEGRADED: checkov not installed — IaC scanning DISABLED (pip3 install checkov | /seatbelt doctor)" >&2
    exit 0
fi

# ── Extract staged IaC files to temp dir ──────────────────────────
# Each staged file is extracted individually via `git show ":path"`.
# Known limitation: multi-file IaC configs (e.g. Terraform modules with
# relative `source` paths) that span multiple staged files may produce
# parse errors in checkov because neighbour files are absent from SCAN_DIR.
# Those files are skipped (fail-open) with a SEATBELT warning on stderr.
SCAN_DIR=$(mktemp -d)
trap 'rm -rf "$SCAN_DIR"' EXIT

BLOCKED=0
BLOCK_DETAILS=""
EXTRACTED=0
EXPECTED=0
while IFS= read -r -d '' staged_file; do
    [ -z "$staged_file" ] && continue

    FRAMEWORK=""
    case "$staged_file" in
        *Dockerfile*|*dockerfile*)                              FRAMEWORK="dockerfile" ;;
        *.tf|*.tf.json)                                         FRAMEWORK="terraform" ;;
        *docker-compose*.yml|*docker-compose*.yaml)             FRAMEWORK="docker_compose" ;;
        .github/workflows/*.yml|.github/workflows/*.yaml)       FRAMEWORK="github_actions" ;;
        *k8s*/*.yml|*k8s*/*.yaml|*kubernetes*/*.yml|*kubernetes*/*.yaml) FRAMEWORK="kubernetes" ;;
        *helm*/*.yml|*helm*/*.yaml)                             FRAMEWORK="helm" ;;
        *)                                                      continue ;;
    esac

    # Skip symlinks (mode 120000) and submodules (mode 160000)
    local_mode=$(git ls-files -s -- "$staged_file" 2>/dev/null | cut -d' ' -f1)
    [ "$local_mode" = "120000" ] || [ "$local_mode" = "160000" ] && continue

    EXPECTED=$((EXPECTED + 1))
    mkdir -p "$SCAN_DIR/$(dirname "$staged_file")" 2>/dev/null || continue
    git show ":$staged_file" > "$SCAN_DIR/$staged_file" 2>/dev/null || continue
    EXTRACTED=$((EXTRACTED + 1))

    OUTPUT=$($CHECKOV_CMD --file "$SCAN_DIR/$staged_file" --framework "$FRAMEWORK" --compact --quiet 2>&1) || true
    FAILED=$(echo "$OUTPUT" | grep -c "FAILED" 2>/dev/null || true)
    FAILED=${FAILED:-0}
    PARSE_ERRORS=$(echo "$OUTPUT" | grep -cE "Parsing errors:" 2>/dev/null || true)
    PARSE_ERRORS=${PARSE_ERRORS:-0}

    if [ "$FAILED" -gt 0 ]; then
        BLOCKED=1
        BLOCK_DETAILS="${BLOCK_DETAILS}$(echo "$OUTPUT" | grep "FAILED" | head -3)\n"
    elif [ "$PARSE_ERRORS" -gt 0 ]; then
        echo "SEATBELT: checkov parse error in $(basename "$staged_file") — skipping" >&2
    fi
done < <(git diff -z --cached --name-only --diff-filter=ACMR 2>/dev/null)

[ "$EXPECTED" -eq 0 ] && exit 0

if [ "$EXTRACTED" -lt "$EXPECTED" ]; then
    echo "SEATBELT: checkov: extracted $EXTRACTED/$EXPECTED staged files (some skipped)" >&2
fi

# ── Emit results ────────────────────────────────────────────────────
if [ "$BLOCKED" = "1" ]; then
    REASON="IaC MISCONFIGURATION in staged files — commit blocked.

checkov found failed checks:

$(printf '%b' "$BLOCK_DETAILS")

Fix: Address the failed checks listed above.
False positive? Add #checkov:skip=CKV_XXX:reason above the affected line
Bypass once: export SKIP_CHECKOV=1 in your shell, then retry"
    block_emit "$REASON"
fi

exit 0
