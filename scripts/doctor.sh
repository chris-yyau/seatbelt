#!/usr/bin/env bash
# Seatbelt doctor: detect installed scanners and report status as JSON
set -euo pipefail

# ── Helper: check tool and get version ──────────────────────────────
check_tool() {
    local name="$1"
    local version_cmd="$2"
    local path=""
    local version=""
    local installed=false

    path=$(command -v "$name" 2>/dev/null || true)
    if [ -n "$path" ]; then
        installed=true
        version=$(eval "$version_cmd" 2>/dev/null | head -1 || true)
    fi

    # checkov fallback: python3 -m checkov
    if [ "$installed" = "false" ] && [ "$name" = "checkov" ]; then
        if python3 -c "import checkov" &>/dev/null 2>&1; then
            installed=true
            path="python3 -m checkov.main"
            version=$(python3 -m checkov.main --version 2>/dev/null | head -1 || true)
        fi
    fi

    printf '{"installed":%s,"version":%s,"path":%s}' \
        "$installed" \
        "$([ -n "$version" ] && printf '"%s"' "$version" || printf 'null')" \
        "$([ -n "$path" ] && printf '"%s"' "$path" || printf 'null')"
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
GITLEAKS=$(check_tool "gitleaks" "gitleaks version")
CHECKOV=$(check_tool "checkov" "checkov --version")
TRIVY=$(check_tool "trivy" "trivy --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'")
ZIZMOR=$(check_tool "zizmor" "zizmor --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'")

# ── Output JSON ─────────────────────────────────────────────────────
cat <<EOF
{"gitleaks":${GITLEAKS},"checkov":${CHECKOV},"trivy":${TRIVY},"zizmor":${ZIZMOR},"platform":"${PLATFORM}","package_managers":[${PMS}]}
EOF
