#!/usr/bin/env bash
# Shared block emission helper for seatbelt scanners.
# Usage: source this file, then call block_emit "scanner_name" "reason text"
# Respects SEATBELT_STRICT: if false, emits warning instead of block.
#
# Result-file writing is NOT done here to avoid double-counting with scanner
# result files. Scanners own their result-file entries. For blockers that are
# downgraded (gitleaks/checkov in strict=false), the scanner writes the
# advisory result file after calling block_emit.

block_emit() {
    local scanner="$1" reason="$2"
    if [ "${SEATBELT_STRICT:-true}" = "false" ]; then
        echo "SEATBELT: $scanner would block: $reason" >&2
    elif command -v jq &>/dev/null; then
        jq -n --arg r "$reason" '{"decision":"block","reason":$r}'
    else
        local escaped
        escaped=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | head -c 2000)
        printf '{"decision":"block","reason":"%s"}\n' "$escaped"
    fi
}

# Severity comparison helper.
# Usage: _seatbelt_severity_at_or_above "finding_sev" "threshold_sev" "low,medium,high"
# Returns 0 if finding >= threshold on the given scale, 1 otherwise.
# Case-insensitive comparison.
_seatbelt_severity_at_or_above() {
    local finding threshold scale
    finding=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    threshold=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
    scale=$(printf '%s' "$3" | tr '[:upper:]' '[:lower:]')
    local IFS=','
    local found_threshold=0
    for level in $scale; do
        [ "$level" = "$threshold" ] && found_threshold=1
        if [ "$found_threshold" -eq 1 ] && [ "$level" = "$finding" ]; then
            return 0
        fi
    done
    return 1
}

# Validate severity value against scanner's scale.
# Usage: _seatbelt_validate_severity "scanner" "value" "LOW,MEDIUM,HIGH"
# Emits warning to stderr if invalid. Returns 1 if invalid, 0 if valid.
_seatbelt_validate_severity() {
    local scanner="$1" value="$2" scale="$3"
    [ -z "$value" ] && return 0
    local normalized
    normalized=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
    local lower_scale
    lower_scale=$(printf '%s' "$scale" | tr '[:upper:]' '[:lower:]')
    if ! echo ",$lower_scale," | grep -qF ",$normalized,"; then
        echo "SEATBELT: $scanner: unknown severity '$value' — ignoring" >&2
        return 1
    fi
    return 0
}
