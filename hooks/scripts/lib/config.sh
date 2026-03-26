#!/usr/bin/env bash
# Shared config loader for seatbelt hooks.
# Usage: source this file to set SEATBELT_* vars.
# Reads .seatbelt.yml from the git repo root.
# Fail-open: missing file, bad YAML, or missing python3 -> all defaults.
#
# Precedence (highest wins): Env var > Config file > Default
# Python outputs _SEATBELT_CFG_* prefix vars for config values only.
# Bash handles precedence: env var overrides config, config overrides default.
#
# v6 fields: strict, severity (trivy/semgrep/zizmor), ruleset (semgrep),
# timeout (all scanners). All string values are shell-escaped via shlex.quote().

_seatbelt_config_file=""
_seatbelt_repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$_seatbelt_repo_root" ] && [ -f "$_seatbelt_repo_root/.seatbelt.yml" ]; then
    _seatbelt_config_file="$_seatbelt_repo_root/.seatbelt.yml"
fi

# Parse config file into _SEATBELT_CFG_* prefix vars (only for fields
# explicitly mentioned in the YAML — omitted fields get no CFG var).
if [ -n "$_seatbelt_config_file" ] && command -v python3 &>/dev/null; then
    # IMPORTANT: Use single-quotes for python3 -c to avoid nested double-quote
    # shell quoting bugs. Config path passed via env var, not sys.argv.
    eval "$(_SEATBELT_CFG="$_seatbelt_config_file" python3 -c '
import os, re, shlex, sys
try:
    cfg_path = os.environ["_SEATBELT_CFG"]
    try:
        import yaml
        with open(cfg_path) as f:
            cfg = yaml.safe_load(f) or {}
    except ImportError:
        sys.stderr.write("SEATBELT: PyYAML not installed — config uses limited fallback (pip3 install pyyaml)\n")
        cfg = {"scanners": {}}
        with open(cfg_path) as f:
            content = f.read()
        # Parse strict at root level
        m = re.search(r"(?m)^\s*strict:\s*(true|false)", content)
        if m:
            cfg["strict"] = m.group(1) == "true"
        # Parse per-scanner fields
        scanner_names = ["gitleaks", "checkov", "trivy", "zizmor", "semgrep", "shellcheck", "commitlint", "signing"]
        for name in scanner_names:
            pattern = r"(?m)^\s*" + name + r":\s*\n((?:\s+\w+:.*\n)*)"
            block_match = re.search(pattern, content)
            if block_match:
                block = block_match.group(0)
                scanner = {}
                em = re.search(r"(?m)^\s+enabled:\s*(true|false)", block)
                if em:
                    scanner["enabled"] = em.group(1) == "true"
                sm = re.search(r"(?m)^\s+severity:\s*(\S+)", block)
                if sm:
                    scanner["severity"] = sm.group(1)
                rm = re.search(r"(?m)^\s+ruleset:\s*(\S+)", block)
                if rm:
                    scanner["ruleset"] = rm.group(1)
                tm = re.search(r"(?m)^\s+timeout:\s*(\d+)", block)
                if tm:
                    scanner["timeout"] = int(tm.group(1))
                if scanner:
                    cfg.setdefault("scanners", {})[name] = scanner
        # Warn if advanced fields present without PyYAML
        has_advanced = any(
            re.search(r"(?m)^\s+" + f, content)
            for f in ["severity:", "ruleset:", "timeout:"]
        )
        if has_advanced:
            sys.stderr.write("SEATBELT: PyYAML not installed — advanced config fields may not parse correctly\n")
    except Exception:
        cfg = {}

    # Output strict
    if "strict" in cfg:
        val = "true" if cfg["strict"] else "false"
        print("_SEATBELT_CFG_STRICT=" + val)

    scanners = cfg.get("scanners", {}) or {}
    for name in ["gitleaks", "checkov", "trivy", "zizmor", "semgrep", "shellcheck", "commitlint", "signing"]:
        s = scanners.get(name) or {}
        if not isinstance(s, dict):
            continue
        if "enabled" in s:
            val = "true" if s["enabled"] else "false"
            print("_SEATBELT_CFG_" + name.upper() + "_ENABLED=" + val)
        if "severity" in s and s["severity"]:
            print("_SEATBELT_CFG_" + name.upper() + "_SEVERITY=" + shlex.quote(str(s["severity"])))
        if "ruleset" in s and s["ruleset"]:
            print("_SEATBELT_CFG_" + name.upper() + "_RULESET=" + shlex.quote(str(s["ruleset"])))
        if "timeout" in s and s["timeout"] is not None:
            print("_SEATBELT_CFG_" + name.upper() + "_TIMEOUT=" + str(int(s["timeout"])))
except Exception:
    pass
' 2>/dev/null || true)"
fi

# ── Apply precedence: Env var > Config file > Default ────────────

# Enabled flags (default: true)
SEATBELT_GITLEAKS_ENABLED="${SEATBELT_GITLEAKS_ENABLED:-${_SEATBELT_CFG_GITLEAKS_ENABLED:-true}}"
SEATBELT_CHECKOV_ENABLED="${SEATBELT_CHECKOV_ENABLED:-${_SEATBELT_CFG_CHECKOV_ENABLED:-true}}"
SEATBELT_TRIVY_ENABLED="${SEATBELT_TRIVY_ENABLED:-${_SEATBELT_CFG_TRIVY_ENABLED:-true}}"
SEATBELT_ZIZMOR_ENABLED="${SEATBELT_ZIZMOR_ENABLED:-${_SEATBELT_CFG_ZIZMOR_ENABLED:-true}}"
SEATBELT_SEMGREP_ENABLED="${SEATBELT_SEMGREP_ENABLED:-${_SEATBELT_CFG_SEMGREP_ENABLED:-true}}"
SEATBELT_SHELLCHECK_ENABLED="${SEATBELT_SHELLCHECK_ENABLED:-${_SEATBELT_CFG_SHELLCHECK_ENABLED:-true}}"
SEATBELT_COMMITLINT_ENABLED="${SEATBELT_COMMITLINT_ENABLED:-${_SEATBELT_CFG_COMMITLINT_ENABLED:-true}}"
SEATBELT_SIGNING_ENABLED="${SEATBELT_SIGNING_ENABLED:-${_SEATBELT_CFG_SIGNING_ENABLED:-true}}"

# Strict mode (default: true)
SEATBELT_STRICT="${SEATBELT_STRICT:-${_SEATBELT_CFG_STRICT:-true}}"

# Severity (presence-based: empty env var = clear config back to warn-only)
if [ -z "${SEATBELT_TRIVY_SEVERITY+set}" ]; then
    SEATBELT_TRIVY_SEVERITY="${_SEATBELT_CFG_TRIVY_SEVERITY:-}"
fi
if [ -z "${SEATBELT_SEMGREP_SEVERITY+set}" ]; then
    SEATBELT_SEMGREP_SEVERITY="${_SEATBELT_CFG_SEMGREP_SEVERITY:-}"
fi
if [ -z "${SEATBELT_ZIZMOR_SEVERITY+set}" ]; then
    SEATBELT_ZIZMOR_SEVERITY="${_SEATBELT_CFG_ZIZMOR_SEVERITY:-}"
fi

# Ruleset (default: p/security-audit)
SEATBELT_SEMGREP_RULESET="${SEATBELT_SEMGREP_RULESET:-${_SEATBELT_CFG_SEMGREP_RULESET:-p/security-audit}}"

# Timeouts (scanner-specific defaults; empty = no timeout)
SEATBELT_TRIVY_TIMEOUT="${SEATBELT_TRIVY_TIMEOUT:-${_SEATBELT_CFG_TRIVY_TIMEOUT:-30}}"
SEATBELT_SEMGREP_TIMEOUT="${SEATBELT_SEMGREP_TIMEOUT:-${_SEATBELT_CFG_SEMGREP_TIMEOUT:-60}}"
SEATBELT_SHELLCHECK_TIMEOUT="${SEATBELT_SHELLCHECK_TIMEOUT:-${_SEATBELT_CFG_SHELLCHECK_TIMEOUT:-30}}"
SEATBELT_CHECKOV_TIMEOUT="${SEATBELT_CHECKOV_TIMEOUT:-${_SEATBELT_CFG_CHECKOV_TIMEOUT:-}}"
SEATBELT_GITLEAKS_TIMEOUT="${SEATBELT_GITLEAKS_TIMEOUT:-${_SEATBELT_CFG_GITLEAKS_TIMEOUT:-}}"
SEATBELT_ZIZMOR_TIMEOUT="${SEATBELT_ZIZMOR_TIMEOUT:-${_SEATBELT_CFG_ZIZMOR_TIMEOUT:-}}"
SEATBELT_COMMITLINT_TIMEOUT="${SEATBELT_COMMITLINT_TIMEOUT:-${_SEATBELT_CFG_COMMITLINT_TIMEOUT:-}}"
SEATBELT_SIGNING_TIMEOUT="${SEATBELT_SIGNING_TIMEOUT:-${_SEATBELT_CFG_SIGNING_TIMEOUT:-}}"

# ── Clean up internal vars ───────────────────────────────────────
unset _seatbelt_config_file _seatbelt_repo_root
unset _SEATBELT_CFG_STRICT
unset _SEATBELT_CFG_GITLEAKS_ENABLED _SEATBELT_CFG_CHECKOV_ENABLED
unset _SEATBELT_CFG_TRIVY_ENABLED _SEATBELT_CFG_ZIZMOR_ENABLED _SEATBELT_CFG_SEMGREP_ENABLED
unset _SEATBELT_CFG_SHELLCHECK_ENABLED _SEATBELT_CFG_COMMITLINT_ENABLED _SEATBELT_CFG_SIGNING_ENABLED
unset _SEATBELT_CFG_TRIVY_SEVERITY _SEATBELT_CFG_SEMGREP_SEVERITY _SEATBELT_CFG_ZIZMOR_SEVERITY
unset _SEATBELT_CFG_SEMGREP_RULESET
unset _SEATBELT_CFG_TRIVY_TIMEOUT _SEATBELT_CFG_SEMGREP_TIMEOUT _SEATBELT_CFG_SHELLCHECK_TIMEOUT
unset _SEATBELT_CFG_CHECKOV_TIMEOUT _SEATBELT_CFG_GITLEAKS_TIMEOUT _SEATBELT_CFG_ZIZMOR_TIMEOUT
unset _SEATBELT_CFG_COMMITLINT_TIMEOUT _SEATBELT_CFG_SIGNING_TIMEOUT
