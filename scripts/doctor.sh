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

# ── Helper: get recommended install command ───────────────────────────
get_install_cmd() {
    local name="$1"
    local has_brew="false"
    local has_pip3="false"
    local has_cargo="false"
    local has_apt="false"
    local has_go="false"

    if echo "$PMS_RAW" | grep -qw "brew";    then has_brew="true";  fi
    if echo "$PMS_RAW" | grep -qw "pip3";    then has_pip3="true";  fi
    if echo "$PMS_RAW" | grep -qw "cargo";   then has_cargo="true"; fi
    if echo "$PMS_RAW" | grep -qw "apt-get"; then has_apt="true";   fi
    if echo "$PMS_RAW" | grep -qw "go";      then has_go="true";    fi

    case "$name" in
        gitleaks)
            if [ "$has_brew" = "true" ]; then
                echo "brew install gitleaks"
            elif [ "$has_apt" = "true" ]; then
                echo "apt-get install gitleaks"
            elif [ "$has_go" = "true" ]; then
                echo "go install github.com/gitleaks/gitleaks/v8@latest"
            else
                echo "https://github.com/gitleaks/gitleaks/releases"
            fi
            ;;
        checkov)
            if [ "$has_pip3" = "true" ]; then
                echo "pip3 install checkov"
            elif [ "$has_brew" = "true" ]; then
                echo "brew install checkov"
            else
                echo "https://www.checkov.io/2.Basics/Installing%20Checkov.html"
            fi
            ;;
        trivy)
            if [ "$has_brew" = "true" ]; then
                echo "brew install trivy"
            elif [ "$has_apt" = "true" ]; then
                echo "curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin"
            else
                echo "https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
            fi
            ;;
        zizmor)
            if [ "$has_pip3" = "true" ]; then
                echo "pip3 install zizmor"
            elif [ "$has_cargo" = "true" ]; then
                echo "cargo install zizmor"
            elif [ "$has_brew" = "true" ]; then
                echo "brew install zizmor"
            else
                echo "https://woodruffw.github.io/zizmor/installation/"
            fi
            ;;
    esac
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

    # Compute install_cmd (null when installed, command string when missing)
    local install_cmd="null"
    if [ "$installed" = "false" ]; then
        install_cmd="$(json_str "$(get_install_cmd "$name")")"
    fi

    # Trivy gets an extra db_cached field
    if [ "$name" = "trivy" ]; then
        local db_cached
        db_cached=$(check_trivy_db)
        printf '{"installed":%s,"version":%s,"path":%s,"db_cached":%s,"install_cmd":%s}' \
            "$installed" \
            "$(json_str "$version")" \
            "$(json_str "$path")" \
            "$db_cached" \
            "$install_cmd"
    else
        printf '{"installed":%s,"version":%s,"path":%s,"install_cmd":%s}' \
            "$installed" \
            "$(json_str "$version")" \
            "$(json_str "$path")" \
            "$install_cmd"
    fi
}

# ── Detect platform ────────────────────────────────────────────────
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"

# ── Detect package managers (raw list for get_install_cmd) ───────────
PMS_RAW=""
for pm in brew pip3 cargo apt-get go; do
    if command -v "$pm" &>/dev/null; then
        PMS_RAW="$PMS_RAW $pm"
    fi
done

# ── Build package managers JSON array ────────────────────────────────
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
