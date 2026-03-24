#!/usr/bin/env bash
# Seatbelt doctor: detect installed scanners and report status as JSON
set -euo pipefail

# ── Helper: JSON-escape a string via python3 ────────────────────────
json_str() {
    local val="$1"
    if [ -z "$val" ]; then
        printf 'null'
    elif command -v python3 &>/dev/null; then
        python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$val" | tr -d '\n'
    else
        # Fallback: escape quotes and backslashes
        local escaped
        escaped=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
        printf '"%s"' "$escaped"
    fi
}

# ── Helper: get version for a known tool ─────────────────────────────
get_version() {
    local name="$1"
    case "$name" in
        gitleaks) gitleaks version 2>/dev/null | head -1 ;;
        checkov)  checkov --version 2>/dev/null | head -1 ;;
        trivy)    trivy --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
        zizmor)   zizmor --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    esac
}

# ── Helper: check if trivy DB is cached ──────────────────────────────
check_trivy_db() {
    local db_dir=""

    if [ -n "${TRIVY_CACHE_DIR:-}" ]; then
        db_dir="${TRIVY_CACHE_DIR}/db"
    elif [ "$(uname -s)" = "Darwin" ]; then
        db_dir="${HOME}/Library/Caches/trivy/db"
    else
        db_dir="${HOME}/.cache/trivy/db"
    fi

    if [ -d "$db_dir" ] && [ -n "$(ls -A "$db_dir" 2>/dev/null)" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# ── Helper: check tool and get version ──────────────────────────────
check_tool() {
    local name="$1"
    local path=""
    local version=""
    local installed=false

    path=$(command -v "$name" 2>/dev/null || true)
    if [ -n "$path" ]; then
        installed=true
        version=$(get_version "$name" || true)
    fi

    # checkov fallback: python3 -m checkov
    if [ "$installed" = "false" ] && [ "$name" = "checkov" ]; then
        if python3 -c "import checkov" &>/dev/null 2>&1; then
            installed=true
            path="python3 -m checkov.main"
            version=$(python3 -m checkov.main --version 2>/dev/null | head -1 || true)
        fi
    fi

    # Trivy gets an extra db_cached field
    if [ "$name" = "trivy" ]; then
        local db_cached
        db_cached=$(check_trivy_db)
        printf '{"installed":%s,"version":%s,"path":%s,"db_cached":%s}' \
            "$installed" \
            "$(json_str "$version")" \
            "$(json_str "$path")" \
            "$db_cached"
    else
        printf '{"installed":%s,"version":%s,"path":%s}' \
            "$installed" \
            "$(json_str "$version")" \
            "$(json_str "$path")"
    fi
}

# ── Detect platform ────────────────────────────────────────────────
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"

# ── Detect package managers ─────────────────────────────────────────
PMS=""
for pm in brew pip3 cargo apt-get go; do
    if command -v "$pm" &>/dev/null; then
        [ -n "$PMS" ] && PMS="${PMS},"
        PMS="${PMS}\"${pm}\""
    fi
done

# ── Check each scanner ─────────────────────────────────────────────
GITLEAKS=$(check_tool "gitleaks")
CHECKOV=$(check_tool "checkov")
TRIVY=$(check_tool "trivy")
ZIZMOR=$(check_tool "zizmor")

# ── Compute health score ─────────────────────────────────────────────
INSTALLED_COUNT=0
for check_var in "$GITLEAKS" "$CHECKOV" "$TRIVY" "$ZIZMOR"; do
    case "$check_var" in
        *'"installed":true'*) INSTALLED_COUNT=$((INSTALLED_COUNT + 1)) ;;
    esac
done
HEALTH="{\"installed\":${INSTALLED_COUNT},\"total\":4,\"score\":\"${INSTALLED_COUNT}/4\"}"

# ── Output JSON ─────────────────────────────────────────────────────
cat <<EOF
{"health":${HEALTH},"gitleaks":${GITLEAKS},"checkov":${CHECKOV},"trivy":${TRIVY},"zizmor":${ZIZMOR},"platform":"${PLATFORM}","package_managers":[${PMS}]}
EOF
