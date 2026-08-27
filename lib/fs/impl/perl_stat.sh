#!/usr/bin/env bash
# =============================================================================
# nutshell/core/fs/impl/perl_stat.sh - perl fallback for fs stat operations
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# This file provides perl-based implementation of fs_size and fs_mtime.
# When sourced, it REPLACES the stubs in fs.sh with the real functions.
# Can also be executed directly for standalone use/testing.
#
# This is a fallback for when stat is unavailable or has unknown variant.
# Perl's stat() is consistent across platforms.
# =============================================================================

# Implementation function for fs_size (internal)
_fs_size_perl_impl() {
    local path="${1:-}"
    [[ ! -f "$path" ]] && return 1
    
    local perl_path="${_TOOL_PATH[perl]:-perl}"
    
    # perl stat returns list: (dev, ino, mode, nlink, uid, gid, rdev, size, ...)
    # Index 7 is size
    "$perl_path" -e 'print((stat($ARGV[0]))[7])' "$path"
}

# Implementation function for fs_mtime (internal)
_fs_mtime_perl_impl() {
    local path="${1:-}"
    [[ ! -e "$path" ]] && return 1
    
    local perl_path="${_TOOL_PATH[perl]:-perl}"
    
    # perl stat returns list: (..., atime, mtime, ctime)
    # Index 9 is mtime
    "$perl_path" -e 'print((stat($ARGV[0]))[9])' "$path"
}

# When sourced: redefine the public functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    fs_size() {
        _fs_size_perl_impl "$@"
    }
    
    fs_mtime() {
        _fs_mtime_perl_impl "$@"
    }
fi
