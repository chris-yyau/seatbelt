#!/usr/bin/env bash
# Shared result directory computation for seatbelt hooks.
# Usage: source this file to set SEATBELT_RESULT_DIR.
# Uses a repo-specific hash to avoid collisions between concurrent commits
# in different repos/worktrees. Override with SEATBELT_RESULT_DIR env var.

if [ -z "${SEATBELT_RESULT_DIR:-}" ]; then
    _seatbelt_base="${TMPDIR:-/tmp}"
    _seatbelt_toplevel=$(git rev-parse --show-toplevel 2>/dev/null || echo "unknown")
    # Try multiple hash commands for portability (macOS: shasum, Linux: sha256sum, fallback: md5sum/cksum)
    _seatbelt_hash=""
    if command -v shasum &>/dev/null; then
        _seatbelt_hash=$(printf '%s' "$_seatbelt_toplevel" | shasum -a 256 | cut -c1-8)
    elif command -v sha256sum &>/dev/null; then
        _seatbelt_hash=$(printf '%s' "$_seatbelt_toplevel" | sha256sum | cut -c1-8)
    elif command -v md5sum &>/dev/null; then
        _seatbelt_hash=$(printf '%s' "$_seatbelt_toplevel" | md5sum | cut -c1-8)
    elif command -v cksum &>/dev/null; then
        _seatbelt_hash=$(printf '%s' "$_seatbelt_toplevel" | cksum | cut -d' ' -f1)
    fi
    # Final fallback: sanitize the path into a safe directory name component
    if [ -z "$_seatbelt_hash" ]; then
        _seatbelt_hash=$(printf '%s' "$_seatbelt_toplevel" | tr '/' '_' | tr -cd '[:alnum:]_-')
    fi
    SEATBELT_RESULT_DIR="${_seatbelt_base}/seatbelt-results-${_seatbelt_hash}"
    unset _seatbelt_base _seatbelt_toplevel _seatbelt_hash
fi
