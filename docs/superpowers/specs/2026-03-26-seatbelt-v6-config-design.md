# Seatbelt v6 — Advanced Scanner Configuration

<!-- design-reviewed: PASS -->

## Summary

Expand `.seatbelt.yml` from simple on/off toggles to richer per-scanner configuration: global strict mode, severity-gated blocking for scanners that support it, custom rulesets, and per-scanner timeouts. Default behavior is unchanged from v5 — new features are opt-in.

## Motivation

Seatbelt v5 has 8 scanners with hardcoded behavior: gitleaks/checkov always block, everything else warns. The only config is `enabled: true/false`. Users need:

- A way to temporarily downgrade blockers for onboarding or CI experiments
- Severity thresholds to promote warn-only scanners to blocking when findings are severe enough
- Custom rulesets for semgrep (different teams want different rule packs)
- Timeout overrides for slow scanners on large repos

## Design Principles

1. **Opinionated defaults** — zero-config works identically to v5
2. **Config knobs only where the underlying tool has meaningful gradations** — severity thresholds only on trivy/semgrep/zizmor (the 3 that support it)
3. **Gate, not filter** — severity threshold controls what blocks; lower-severity findings still warn. The `--severity` flag passed to each tool is NOT changed by config — trivy always scans HIGH,CRITICAL regardless.
4. **No contradictory config** — no per-scanner block/warn toggle alongside severity. Severity IS the blocking control.
5. **Fail-open** — invalid config values, timeouts, and missing tools degrade gracefully with warnings

## Config Schema

```yaml
# .seatbelt.yml
strict: true  # default true. false = all blockers downgrade to warnings

scanners:
  gitleaks:
    enabled: true
  checkov:
    enabled: true
    timeout: 60
  trivy:
    enabled: true
    severity: CRITICAL      # block on CRITICAL, warn on HIGH (default: empty = warn-only)
    timeout: 45
  semgrep:
    enabled: true
    severity: error         # block on error, warn on warning/info (default: empty = warn-only)
    ruleset: p/owasp-top-ten  # override default p/security-audit (single ruleset, passed verbatim to --config)
    timeout: 60
  zizmor:
    enabled: true
    severity: high          # block on high+, warn on lower (default: empty = warn-only)
  shellcheck:
    enabled: true
    timeout: 30
  commitlint:
    enabled: true
  signing:
    enabled: true
```

### Field Reference

| Field | Applies to | Type | Default | Description |
|-------|-----------|------|---------|-------------|
| `strict` | global | bool | `true` | `false` downgrades all block decisions to warnings |
| `enabled` | all scanners | bool | `true` | Enable/disable scanner |
| `severity` | trivy, semgrep, zizmor | string | *(empty)* | Findings at/above this level block; below this level warn. Empty = warn-only (v5 behavior). |
| `timeout` | all scanners | int (seconds) | scanner-specific (see below) | Per-scanner timeout override |
| `ruleset` | semgrep | string | `p/security-audit` | Semgrep ruleset identifier (single value, passed verbatim to `--config`) |

### Severity Scales

Each scanner has its own severity scale. Values are compared **case-insensitively** and normalized to the scanner's native case before use.

| Scanner | Severity scale (low → high) | Default severity | Behavior with no config |
|---------|----------------------------|-----------------|------------------------|
| trivy | HIGH, CRITICAL | *(empty)* | Warn-only on HIGH+ findings (v5 behavior). Trivy always scans with `--severity HIGH,CRITICAL` — the severity config field controls only the block/warn decision, not the `--severity` filter flag. Only HIGH and CRITICAL are valid thresholds since trivy only returns those severities. |
| semgrep | info, warning, error | *(empty)* | Warn-only (no blocking) |
| zizmor | low, medium, high | *(empty)* | Warn-only (no blocking) |

**Opting into blocking:** Setting any `severity` value explicitly opts that scanner into blocking at that threshold. To preserve exact v5 warn-only behavior, omit the severity field entirely.

**Invalid severity values:** If a severity value does not match the scanner's known scale (case-insensitive), emit a warning on stderr (`SEATBELT: <scanner>: unknown severity '<value>' — ignoring`) and treat as empty (warn-only).

### Severity Gating Logic

When `severity` is set for a scanner, the scanner classifies each finding against the threshold:

- **Finding severity >= threshold** → emit `{"decision":"block",...}` on stdout (unless `strict: false`)
- **Finding severity < threshold** → emit warning on stderr (same as v5)

The underlying tool's `--severity` filter flag is **not changed** by the config severity field. Trivy always passes `--severity HIGH,CRITICAL`. The config severity only gates the block/warn decision on the findings that come back.

### Strict Mode Interaction

When `strict: false`:
- Scanners that normally block (gitleaks, checkov) emit warnings on stderr instead of block decisions on stdout
- Severity thresholds are still evaluated for annotation, but block decisions are suppressed to warnings
- `SKIP_<SCANNER>=1` still takes absolute precedence — the scanner exits immediately without reading any config

### Precedence

Highest wins: **Environment variable > Config file > Default**

New env vars:
- `SEATBELT_STRICT` (default: `true`)
- `SEATBELT_TRIVY_SEVERITY` (default: empty = warn-only)
- `SEATBELT_SEMGREP_SEVERITY` (default: empty = warn-only)
- `SEATBELT_ZIZMOR_SEVERITY` (default: empty = warn-only)
- `SEATBELT_SEMGREP_RULESET` (default: `p/security-audit`)
- `SEATBELT_<SCANNER>_TIMEOUT` (defaults match v5: trivy=30, semgrep=60, shellcheck=30; gitleaks/checkov/zizmor/commitlint/signing=none, i.e. no timeout unless configured)

### Unknown Keys

Unknown keys in YAML are silently ignored (forward-compatible).

## Scanner Script Changes

### Shared: `lib/block-emit.sh`

Extract a shared helper for emitting block decisions, sourced by all scanners that support blocking:

```bash
# lib/block-emit.sh
# Usage: block_emit "scanner_name" "reason text"
# Respects SEATBELT_STRICT: if false, emits warning instead of block.
# Extracted from scan-gitleaks.sh's existing implementation.
block_emit() {
    local scanner="$1" reason="$2"
    if [ "${SEATBELT_STRICT:-true}" = "false" ]; then
        echo "SEATBELT: $scanner would block: $reason" >&2
        # Note: advisory result files are written by each scanner after calling
        # block_emit, not by this helper — avoids double-counting.
    elif command -v jq &>/dev/null; then
        jq -n --arg r "$reason" '{"decision":"block","reason":$r}'
    else
        local escaped
        escaped=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ' | head -c 2000)
        printf '{"decision":"block","reason":"%s"}\n' "$escaped"
    fi
}
```

### trivy (`scan-trivy.sh`)

- Read `SEATBELT_TRIVY_SEVERITY` from config. The `--severity HIGH,CRITICAL` flag is **unchanged** — it controls what trivy reports, not what seatbelt blocks on.
- When `SEATBELT_TRIVY_SEVERITY` is non-empty: after parsing JSON results, classify each finding's severity against the threshold. If any finding is at/above the threshold, call `block_emit`.
- When `SEATBELT_TRIVY_SEVERITY` is empty (default): existing v5 warn-only behavior unchanged.
- Read `SEATBELT_TRIVY_TIMEOUT` for portable timeout command.

### semgrep (`scan-semgrep.sh`)

- Read `SEATBELT_SEMGREP_RULESET` and use as `--config` value (default: `p/security-audit`).
- **Invalid ruleset handling:** Capture semgrep stderr (currently discarded with `2>/dev/null`). If semgrep exits non-zero and stderr contains config resolution errors, emit `SEATBELT DEGRADED: semgrep invalid ruleset '<value>' — scan skipped` and exit 0. This prevents a bad ruleset from silently disabling scanning.
- Read `SEATBELT_SEMGREP_SEVERITY`. If non-empty, parse JSON output and classify finding severity against threshold.
- Findings at/above threshold: call `block_emit`.
- Findings below threshold: warn on stderr as before.
- Read `SEATBELT_SEMGREP_TIMEOUT` for timeout.

### zizmor (`scan-zizmor.sh`)

- Read `SEATBELT_ZIZMOR_SEVERITY`. If non-empty, parse JSON output severity field.
- Findings at/above threshold: call `block_emit`.
- Findings below threshold: warn on stderr as before.
- Read `SEATBELT_ZIZMOR_TIMEOUT` for timeout.

### gitleaks (`scan-gitleaks.sh`) and checkov (`scan-checkov.sh`)

- Refactor existing block logic to use shared `block_emit` helper. Behavior unchanged when `strict: true`.
- When `SEATBELT_STRICT=false`: `block_emit` suppresses the block decision to a stderr warning.
- Read `SEATBELT_<NAME>_TIMEOUT` for timeout.

### shellcheck (`scan-shellcheck.sh`)

- Read `SEATBELT_SHELLCHECK_TIMEOUT` for timeout. No severity or ruleset changes.

### commitlint, signing

- Config exposes `SEATBELT_COMMITLINT_TIMEOUT` and `SEATBELT_SIGNING_TIMEOUT` for future use. Current hook implementations do not apply timeouts to these advisory checks (they are fast enough to not need them). No other changes.

### Timeout Behavior

**Timeout scope:** The configured timeout applies per-tool-invocation within the scanner's file loop (matching current behavior). For scanners that invoke the tool once on a directory (semgrep), the timeout wraps that single invocation. For scanners that loop over files (trivy, shellcheck), each file gets its own timeout.

**When a per-invocation timeout expires:**
- That invocation fails open (result treated as empty)
- Emits a degraded warning on stderr: `SEATBELT DEGRADED: <scanner> timed out after N seconds on <file>`
- No block decision is emitted for the timed-out invocation
- Partial result files from earlier loop iterations are preserved (they represent valid findings)

## Config Library Changes (`config.sh`)

### YAML Parser (Python)

The Python YAML parser expands to read `strict`, `severity`, `ruleset`, and `timeout` fields alongside `enabled`. Outputs additional `_SEATBELT_CFG_*` vars:

```text
_SEATBELT_CFG_STRICT
_SEATBELT_CFG_TRIVY_SEVERITY
_SEATBELT_CFG_SEMGREP_SEVERITY
_SEATBELT_CFG_SEMGREP_RULESET
_SEATBELT_CFG_ZIZMOR_SEVERITY
_SEATBELT_CFG_<SCANNER>_TIMEOUT
```

### Regex Fallback Parser

When PyYAML is not installed, the regex fallback parser extends to capture the new fields. For each known scanner name, scan forward from the `name:` line and match all indented `key: value` pairs:

```regex
enabled:\s*(true|false)
severity:\s*(\S+)
ruleset:\s*(\S+)
timeout:\s*(\d+)
```

The global `strict` field is matched at root level: `^\s*strict:\s*(true|false)`.

All regexes are anchored with `^\s*` to avoid matching commented-out lines (e.g. `# severity: HIGH` should not match). Field ordering within a scanner block does not matter — each regex is applied independently to the content between one scanner header and the next.

**Fallback limitations:** The regex parser only supports unquoted simple scalars (e.g. `p/security-audit`, `HIGH`, `60`). Quoted values or values with spaces are not supported. If PyYAML is not installed and advanced fields (severity, ruleset, timeout) are present in config, emit: `SEATBELT: PyYAML not installed — advanced config fields may not parse correctly`.

### Bash Precedence

For severity env vars, use presence-based override (`${VAR+set}` check) instead of `:-`, because an explicitly empty `SEATBELT_TRIVY_SEVERITY=` should clear a repo's configured threshold back to warn-only:

```bash
SEATBELT_STRICT="${SEATBELT_STRICT:-${_SEATBELT_CFG_STRICT:-true}}"

# Severity: empty is meaningful (= warn-only), so use presence-based override
if [ -z "${SEATBELT_TRIVY_SEVERITY+set}" ]; then
    SEATBELT_TRIVY_SEVERITY="${_SEATBELT_CFG_TRIVY_SEVERITY:-}"
fi
# Same pattern for SEMGREP_SEVERITY, ZIZMOR_SEVERITY

# Non-empty-meaningful fields use standard :- pattern
SEATBELT_SEMGREP_RULESET="${SEATBELT_SEMGREP_RULESET:-${_SEATBELT_CFG_SEMGREP_RULESET:-p/security-audit}}"
# Timeout vars: default to scanner-specific v5 values (trivy=30, semgrep=60, etc.)
```

Cleanup: unset all `_SEATBELT_CFG_*` vars after precedence resolution.

## Doctor Changes (`doctor.sh`)

- Report configured severity thresholds in scanner JSON output (new `severity` field per scanner, null if not configured).
- Report `strict` mode status in top-level JSON.
- Health score unchanged from v5.

## Testing Strategy

### New test files

- `tests/test-config-v2.sh` — severity, ruleset, timeout parsing; env var precedence for new fields; unknown keys ignored; invalid severity values produce warning
- `tests/test-strict-mode.sh` — `strict: false` downgrades gitleaks/checkov to warn; `strict: true` unchanged; strict + severity interaction
- `tests/test-severity-gating.sh` — trivy blocks on CRITICAL when configured; semgrep blocks on error; zizmor blocks on high; lower findings still warn; empty severity = warn-only
- `tests/test-timeout-override.sh` — custom timeout passed to timeout command; timeout expiry emits degraded warning
- `tests/test-ruleset.sh` — semgrep uses custom ruleset when configured; default ruleset when not

### New test fixtures

- `tests/fixtures/seatbelt-severity.yml` — config with severity thresholds
- `tests/fixtures/seatbelt-strict-false.yml` — config with `strict: false`
- `tests/fixtures/seatbelt-custom-ruleset.yml` — config with semgrep ruleset override
- `tests/fixtures/seatbelt-timeouts.yml` — config with per-scanner timeouts

### Backward compatibility

- No `.seatbelt.yml` = identical to v5 (121 existing tests pass unchanged)
- Minimal config (`scanners: gitleaks: enabled: true`) = identical to v5

### Estimated new tests: ~30

## Version

Bump to **3.2.0** — new behavior is purely additive and opt-in. No existing behavior changes without explicit config. Defaults are identical to v5.

## Out of Scope

- Per-scanner block/warn toggle (council rejected: creates policy drift)
- Severity thresholds for binary scanners (gitleaks, checkov, commitlint, signing, shellcheck)
- Config inheritance or profiles
- Remote/shared config
- Multi-ruleset support for semgrep (single ruleset only, passed verbatim)
- Changing trivy's `--severity` filter flag via config (config controls block/warn decision only)
