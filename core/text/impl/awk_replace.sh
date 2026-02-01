#!/usr/bin/env bash
# =============================================================================
# nutshell/core/text/impl/awk_replace.sh - awk implementation for text_replace
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# This file provides the awk-based implementation of text_replace.
# When sourced, it REPLACES the stub in text.sh with the real function.
# Can also be executed directly for standalone use/testing.
#
# Note: awk is a fallback when sed and perl aren't available.
# It requires writing to a temp file and moving it back.
# =============================================================================

# Implementation function (internal)
_text_replace_awk_impl() {
    local pattern="${1:-}"
    local replacement="${2:-}"
    local file="${3:-}"
    
    [[ -z "$pattern" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    
    local awk_path="${_TOOL_PATH[awk]:-awk}"
    local mktemp_path="${_TOOL_PATH[mktemp]:-mktemp}"
    
    # awk doesn't have in-place editing; use temp file
    local temp
    temp="$("$mktemp_path" 2>/dev/null)" || temp="/tmp/awk_replace.$$"
    
    # gsub performs global substitution in awk
    # We need to escape special characters in the replacement for awk
    "$awk_path" -v pat="$pattern" -v rep="$replacement" '
    {
        gsub(pat, rep)
        print
    }' "$file" > "$temp"
    
    if [[ $? -eq 0 ]] && [[ -s "$temp" || ! -s "$file" ]]; then
        mv "$temp" "$file"
    else
        rm -f "$temp"
        return 1
    fi
}

# When sourced: redefine the public function
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    text_replace() {
        _text_replace_awk_impl "$@"
    }
fi

# When executed directly: run with provided arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Minimal environment setup for standalone execution
    if [[ -z "${_TOOL_PATH[awk]:-}" ]]; then
        declare -A _TOOL_PATH=()
        _TOOL_PATH[awk]="$(command -v awk 2>/dev/null || echo "awk")"
        _TOOL_PATH[mktemp]="$(command -v mktemp 2>/dev/null || echo "mktemp")"
    fi
    
    _text_replace_awk_impl "$@"
fi
