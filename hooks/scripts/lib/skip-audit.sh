#!/usr/bin/env bash
# Log when a seatbelt scanner is skipped via SKIP_* env vars.
# Usage: source this file, then call seatbelt_log_skip <scanner> <env_var>
# Writes to .claude/bypass-log.jsonl in the repo root (same as litmus gate).
# Fail-open: logging errors never block the commit.

seatbelt_log_skip() {
  local scanner="${1:-unknown}" env_var="${2:-unknown}"
  local repo_root ts head log_file
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  log_file="$repo_root/.claude/bypass-log.jsonl"
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || return 0
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
  head=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  printf '{"ts":"%s","event":"seatbelt-skip","scanner":"%s","reason":"%s","head":"%s"}\n' \
    "$ts" "$scanner" "$env_var" "$head" >> "$log_file" 2>/dev/null || true
}
