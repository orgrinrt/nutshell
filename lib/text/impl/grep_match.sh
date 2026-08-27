#!/usr/bin/env bash
# =============================================================================
# nutshell/core/text/impl/grep_match.sh - grep implementation for text matching
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# This file provides the grep-based implementation of text_grep and text_contains.
# When sourced, it REPLACES the stubs in text.sh with the real functions.
# Can also be executed directly for standalone use/testing.
# =============================================================================

# Implementation function for text_grep (internal)
_text_grep_grep_impl() {
    local pattern="${1:-}"
    local file="${2:-}"
    
    [[ -z "$pattern" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    
    local grep_path="${_TOOL_PATH[grep]:-grep}"
    
    # Use -E for extended regex by default
    "$grep_path" -E "$pattern" "$file" 2>/dev/null || true
}

# Implementation function for text_contains (internal)
_text_contains_grep_impl() {
    local pattern="${1:-}"
    local file="${2:-}"
    
    [[ -z "$pattern" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    
    local grep_path="${_TOOL_PATH[grep]:-grep}"
    
    # -q for quiet mode; just return exit status
    "$grep_path" -qE "$pattern" "$file" 2>/dev/null
}

# Implementation function for text_count_matches (internal)
_text_count_matches_grep_impl() {
    local pattern="${1:-}"
    local file="${2:-}"
    
    [[ -z "$pattern" ]] && { echo "0"; return 1; }
    [[ ! -f "$file" ]] && { echo "0"; return 1; }
    
    local grep_path="${_TOOL_PATH[grep]:-grep}"
    
    # -c counts matching lines
    "$grep_path" -cE "$pattern" "$file" 2>/dev/null || echo "0"
}

# When sourced: redefine the public functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    text_grep() {
        _text_grep_grep_impl "$@"
    }
    
    text_contains() {
        _text_contains_grep_impl "$@"
    }
    
    text_count_matches() {
        _text_count_matches_grep_impl "$@"
    }
fi
