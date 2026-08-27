#!/usr/bin/env bash
# =============================================================================
# nutshell/core/fs/impl/stat_bsd.sh - BSD stat implementation for fs operations
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
    [ ! -f "$path" ] && return 1
    
    local stat_path="${_TOOL_PATH_stat:-stat}"
    
    # BSD stat uses -f for format, %z for size in bytes
    "$stat_path" -f%z "$path"
}

# Implementation function for fs_mtime (internal)
_fs_mtime_stat_bsd_impl() {
    local path="${1:-}"
    [ ! -e "$path" ] && return 1
    
    local stat_path="${_TOOL_PATH_stat:-stat}"
    
    # BSD stat uses -f for format, %m for mtime as epoch seconds
    "$stat_path" -f%m "$path"
}

# Sourced, always: the resolver is the only thing that opens this file, and it
# sources it. The `if [[ "${BASH_SOURCE[0]}" != "${0}" ]]` this replaces asked
# whether that was so, which is a question with one answer and a bad
# substitution under a POSIX shell, where there is no `BASH_SOURCE` to
# subscript.
fs_size() {
    _fs_size_stat_bsd_impl "$@"
}

fs_mtime() {
    _fs_mtime_stat_bsd_impl "$@"
}
