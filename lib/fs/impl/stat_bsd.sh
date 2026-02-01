#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/fs/impl/stat_bsd.sh - BSD stat implementation for fs operations
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# This file provides BSD stat-based implementation of fs_size and fs_mtime.
# When sourced, it REPLACES the stubs in fs.sh with the real functions.
# Can also be executed directly for standalone use/testing.
#
# BSD stat (macOS, FreeBSD, etc.) uses -f for format strings instead of -c.
# =============================================================================

# Implementation function for fs_size (internal)
_fs_size_stat_bsd_impl() {
    local path="${1:-}"
    [[ ! -f "$path" ]] && return 1
    
    local stat_path="${_TOOL_PATH[stat]:-stat}"
    
    # BSD stat uses -f for format, %z for size in bytes
    "$stat_path" -f%z "$path"
}

# Implementation function for fs_mtime (internal)
_fs_mtime_stat_bsd_impl() {
    local path="${1:-}"
    [[ ! -e "$path" ]] && return 1
    
    local stat_path="${_TOOL_PATH[stat]:-stat}"
    
    # BSD stat uses -f for format, %m for mtime as epoch seconds
    "$stat_path" -f%m "$path"
}

# When sourced: redefine the public functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    fs_size() {
        _fs_size_stat_bsd_impl "$@"
    }
    
    fs_mtime() {
        _fs_mtime_stat_bsd_impl "$@"
    }
fi

# When executed directly: dispatch based on first argument
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Minimal environment setup for standalone execution
    if [[ -z "${_TOOL_PATH[stat]:-}" ]]; then
        declare -A _TOOL_PATH=()
        _TOOL_PATH[stat]="$(command -v stat 2>/dev/null || echo "stat")"
    fi
    
    case "${1:-}" in
        --size)
            shift
            _fs_size_stat_bsd_impl "$@"
            ;;
        --mtime)
            shift
            _fs_mtime_stat_bsd_impl "$@"
            ;;
        *)
            echo "Usage: $0 [--size|--mtime] path" >&2
            exit 1
            ;;
    esac
fi
