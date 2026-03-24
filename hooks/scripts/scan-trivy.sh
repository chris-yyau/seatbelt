#!/usr/bin/env bash
# Seatbelt: scan staged lock files for dependency CVEs before git commit
# Scanner: trivy | Fail mode: warn only (never blocks)
# Skip: SKIP_TRIVY=1 or SKIP_SEATBELT=1

set -euo pipefail
trap 'exit 0' ERR  # fail-open on script errors

# ── Skip overrides ──────────────────────────────────────────────────
[ "${SKIP_SEATBELT:-0}" = "1" ] && exit 0
[ "${SKIP_TRIVY:-0}" = "1" ] && exit 0

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

# ── trivy availability ──────────────────────────────────────────────
if ! command -v trivy &>/dev/null; then
    echo "SEATBELT DEGRADED: trivy not installed — dependency CVE scanning DISABLED (brew install trivy | /seatbelt doctor)" >&2
    exit 0
fi

# ── Early exit: no lock files staged ──────────────────────────────
HAS_LOCKFILES=0
while IFS= read -r -d '' path; do
    case "$path" in
        *package-lock.json|*yarn.lock|*pnpm-lock.yaml|*Cargo.lock|*requirements.txt|*poetry.lock|*uv.lock|*Pipfile.lock|*go.sum|*Gemfile.lock|*composer.lock)
            HAS_LOCKFILES=1; break ;;
    esac
done < <(git diff -z --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
[ "$HAS_LOCKFILES" -eq 0 ] && exit 0

# ── Extract staged lock files to temp dir ─────────────────────────
SCAN_DIR=$(mktemp -d)
trap 'rm -rf "$SCAN_DIR"' EXIT

# ── Check trivy DB cache ───────────────────────────────────────────
TRIVY_CACHE="${TRIVY_CACHE_DIR:-}"
if [ -z "$TRIVY_CACHE" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        TRIVY_CACHE="${HOME}/Library/Caches/trivy/db"
    else
        TRIVY_CACHE="${HOME}/.cache/trivy/db"
    fi
else
    TRIVY_CACHE="${TRIVY_CACHE}/db"
fi

if [ ! -d "$TRIVY_CACHE" ] || [ -z "$(ls -A "$TRIVY_CACHE" 2>/dev/null)" ]; then
    echo "SEATBELT: trivy: no vulnerability DB cached — run 'trivy image --download-db-only' to enable dep scanning" >&2
    exit 0
fi

# ── Portable timeout ───────────────────────────────────────────────
TIMEOUT_CMD=""
if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout 30"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout 30"
fi

EXTRACTED=0
EXPECTED=0
while IFS= read -r -d '' lf; do
    [ -z "$lf" ] && continue

    case "$lf" in
        *package-lock.json|*yarn.lock|*pnpm-lock.yaml) ;;
        *Cargo.lock|*requirements.txt|*poetry.lock)     ;;
        *uv.lock|*Pipfile.lock|*go.sum)                 ;;
        *Gemfile.lock|*composer.lock)                    ;;
        *)                                              continue ;;
    esac

    local_mode=$(git ls-files -s -- "$lf" 2>/dev/null | cut -d' ' -f1)
    if [ "$local_mode" = "120000" ] || [ "$local_mode" = "160000" ]; then continue; fi

    EXPECTED=$((EXPECTED + 1))
    mkdir -p "$SCAN_DIR/$(dirname "$lf")" 2>/dev/null || continue
    git show ":$lf" > "$SCAN_DIR/$lf" 2>/dev/null || continue
    EXTRACTED=$((EXTRACTED + 1))

    trivy_stderr=$(mktemp)
    if [ -n "$TIMEOUT_CMD" ]; then
        SCAN_OUTPUT=$($TIMEOUT_CMD trivy fs --scanners vuln --severity HIGH,CRITICAL --skip-db-update --no-progress --format json "$SCAN_DIR/$lf" 2>"$trivy_stderr") || true
    else
        SCAN_OUTPUT=$(trivy fs --scanners vuln --severity HIGH,CRITICAL --skip-db-update --no-progress --format json "$SCAN_DIR/$lf" 2>"$trivy_stderr") || true
    fi

    # Parse JSON for findings
    FINDING_INFO=$(printf '%s' "$SCAN_OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = data.get('Results', []) or []
    total = 0
    summary_lines = []
    for result in results:
        vulns = result.get('Vulnerabilities') or []
        total += len(vulns)
        for v in vulns[:3]:
            vid = v.get('VulnerabilityID', '')
            sev = v.get('Severity', '')
            pkg = v.get('PkgName', '')
            ver = v.get('InstalledVersion', '')
            summary_lines.append(f'  {vid} [{sev}] {pkg} {ver}')
    summary = '; '.join(summary_lines[:5])
    print(f'{total}|{summary}')
except Exception:
    print('-1|')
" 2>/dev/null || echo "-1|")

    FINDING_COUNT="${FINDING_INFO%%|*}"
    FINDING_SUMMARY="${FINDING_INFO#*|}"

    # Handle parse result
    if [ "$FINDING_COUNT" = "-1" ]; then
        # JSON parse failed (truncated output, unexpected format, etc.)
        # Fail-open with a degraded warning rather than silently skipping.
        trivy_err=$(head -3 < "$trivy_stderr" 2>/dev/null || true)
        if [ -n "$trivy_err" ]; then
            echo "SEATBELT: trivy: could not parse scan output for $(basename "$lf") — ${trivy_err}" >&2
        else
            echo "SEATBELT: trivy: could not parse scan output for $(basename "$lf") — scan result unknown" >&2
        fi
    else
        if [ "$FINDING_COUNT" -gt 0 ] 2>/dev/null; then
            echo "SEATBELT: trivy found ${FINDING_COUNT} vulnerabilit$([ "$FINDING_COUNT" -eq 1 ] && echo 'y' || echo 'ies') in $(basename "$lf"):" >&2
            if [ -n "$FINDING_SUMMARY" ]; then
                printf '%s\n' "$FINDING_SUMMARY" >&2
            fi
        fi
    fi
    rm -f "$trivy_stderr"
done < <(git diff -z --cached --name-only --diff-filter=ACMR 2>/dev/null)

[ "$EXPECTED" -eq 0 ] && exit 0

if [ "$EXTRACTED" -lt "$EXPECTED" ]; then
    echo "SEATBELT: trivy: extracted $EXTRACTED/$EXPECTED staged files (some skipped)" >&2
fi

exit 0
