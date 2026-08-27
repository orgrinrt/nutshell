#!/usr/bin/env bash
# =============================================================================
# nutshell/core/text/impl/perl_match.sh - perl implementation for text matching
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# This file provides the perl-based implementation of text_grep and text_contains.
# When sourced, it REPLACES the stubs in text.sh with the real functions.
# Can also be executed directly for standalone use/testing.
#
# Perl is useful when PCRE features are needed that grep -P doesn't support,
# or when perl is available but grep isn't (rare).
# =============================================================================

# Implementation function for text_grep (internal)
_text_grep_perl_impl() {
    local pattern="${1:-}"
    local file="${2:-}"
    
    [[ -z "$pattern" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    
    local perl_path="${_TOOL_PATH_perl:-perl}"
    
    # -n reads line by line; print only lines matching pattern
    "$perl_path" -ne "print if /${pattern}/" "$file" 2>/dev/null || true
}

# Implementation function for text_contains (internal)
_text_contains_perl_impl() {
    local pattern="${1:-}"
    local file="${2:-}"
    
    [[ -z "$pattern" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    
    local perl_path="${_TOOL_PATH_perl:-perl}"
    
    # Exit 0 on first match, 1 if no match
    "$perl_path" -ne "exit 0 if /${pattern}/; END { exit 1 }" "$file" 2>/dev/null
}

# Implementation function for text_count_matches (internal)
_text_count_matches_perl_impl() {
    local pattern="${1:-}"
    local file="${2:-}"
    
    [[ -z "$pattern" ]] && { echo "0"; return 1; }
    [[ ! -f "$file" ]] && { echo "0"; return 1; }
    
    local perl_path="${_TOOL_PATH_perl:-perl}"
    
    # Count lines matching pattern
    "$perl_path" -ne '$c++ if /'"${pattern}"'/; END { print $c // 0 }' "$file" 2>/dev/null || echo "0"
}

# When sourced: redefine the public functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    text_grep() {
        _text_grep_perl_impl "$@"
    }
    
    text_contains() {
        _text_contains_perl_impl "$@"
    }
    
    text_count_matches() {
        _text_count_matches_perl_impl "$@"
    }
fi
