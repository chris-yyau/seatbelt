#!/usr/bin/env bash
# Shared config loader for seatbelt hooks.
# Usage: source this file to set SEATBELT_<SCANNER>_ENABLED vars.
# Reads .seatbelt.yml from the git repo root.
# Fail-open: missing file, bad YAML, or missing python3 -> all enabled.
#
# Precedence (highest wins): Env var > Config file > Default (true)
# Python outputs _SEATBELT_CFG_* prefix vars for config values only.
# Bash handles precedence: env var overrides config, config overrides default.

_seatbelt_config_file=""
_seatbelt_repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$_seatbelt_repo_root" ] && [ -f "$_seatbelt_repo_root/.seatbelt.yml" ]; then
    _seatbelt_config_file="$_seatbelt_repo_root/.seatbelt.yml"
fi

# Parse config file into _SEATBELT_CFG_* prefix vars (only for scanners
# explicitly mentioned in the YAML — omitted scanners get no CFG var).
if [ -n "$_seatbelt_config_file" ] && command -v python3 &>/dev/null; then
    # IMPORTANT: Use single-quotes for python3 -c to avoid nested double-quote
    # shell quoting bugs. Config path passed via env var, not sys.argv.
    eval "$(_SEATBELT_CFG="$_seatbelt_config_file" python3 -c '
import os, re, sys
try:
    cfg_path = os.environ["_SEATBELT_CFG"]
    try:
        import yaml
        with open(cfg_path) as f:
            cfg = yaml.safe_load(f) or {}
    except ImportError:
        # Fallback: regex parse for simple enabled: true/false format
        # Uses (?m)^\s* anchor to avoid substring false matches
        sys.stderr.write("SEATBELT: PyYAML not installed — config uses limited fallback (pip3 install pyyaml)\n")
        cfg = {"scanners": {}}
        with open(cfg_path) as f:
            content = f.read()
        for name in ["gitleaks", "checkov", "trivy", "zizmor", "semgrep"]:
            match = re.search(r"(?m)^\s*" + name + r":\s*\n\s+enabled:\s*(true|false)", content)
            if match:
                cfg.setdefault("scanners", {})[name] = {"enabled": match.group(1) == "true"}
    except Exception:
        cfg = {}
    scanners = cfg.get("scanners", {}) or {}
    # ONLY output vars for scanners explicitly in the YAML (preserves env var precedence)
    for name in ["gitleaks", "checkov", "trivy", "zizmor", "semgrep"]:
        if name in scanners and "enabled" in (scanners.get(name) or {}):
            val = "true" if scanners[name]["enabled"] else "false"
            print("_SEATBELT_CFG_" + name.upper() + "_ENABLED=" + val)
except Exception:
    pass
' 2>/dev/null || true)"
fi

# Apply precedence: Env var > Config file > Default (true)
# If SEATBELT_*_ENABLED is already set in env, it wins.
# Otherwise, use config file value (_SEATBELT_CFG_*).
# Otherwise, default to true.
SEATBELT_GITLEAKS_ENABLED="${SEATBELT_GITLEAKS_ENABLED:-${_SEATBELT_CFG_GITLEAKS_ENABLED:-true}}"
SEATBELT_CHECKOV_ENABLED="${SEATBELT_CHECKOV_ENABLED:-${_SEATBELT_CFG_CHECKOV_ENABLED:-true}}"
SEATBELT_TRIVY_ENABLED="${SEATBELT_TRIVY_ENABLED:-${_SEATBELT_CFG_TRIVY_ENABLED:-true}}"
SEATBELT_ZIZMOR_ENABLED="${SEATBELT_ZIZMOR_ENABLED:-${_SEATBELT_CFG_ZIZMOR_ENABLED:-true}}"
SEATBELT_SEMGREP_ENABLED="${SEATBELT_SEMGREP_ENABLED:-${_SEATBELT_CFG_SEMGREP_ENABLED:-true}}"

# Clean up internal vars
unset _seatbelt_config_file _seatbelt_repo_root
unset _SEATBELT_CFG_GITLEAKS_ENABLED _SEATBELT_CFG_CHECKOV_ENABLED
unset _SEATBELT_CFG_TRIVY_ENABLED _SEATBELT_CFG_ZIZMOR_ENABLED _SEATBELT_CFG_SEMGREP_ENABLED
