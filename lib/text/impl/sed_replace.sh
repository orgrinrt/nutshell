#!/usr/bin/env bash
# =============================================================================
# nutshell/core/text/impl/sed_replace.sh - sed implementation for text_replace
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# This file provides the sed-based implementation of text_replace.
# When sourced, it REPLACES the stub in text.sh with the real function.
# Can also be executed directly for standalone use/testing.
# =============================================================================

# Implementation function (internal)
_text_replace_sed_impl() {
    local pattern="${1:-}"
    local replacement="${2:-}"
    local file="${3:-}"
    
    [[ -z "$pattern" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    
    local sed_path="${_TOOL_PATH[sed]:-sed}"
    local variant="${_TOOL_VARIANT[sed]:-unknown}"
    
    if [[ "$variant" == "gnu" ]]; then
        "$sed_path" -i "s/${pattern}/${replacement}/g" "$file"
    else
        # BSD sed requires '' after -i for no backup
        "$sed_path" -i '' "s/${pattern}/${replacement}/g" "$file"
    fi
}

# When sourced: redefine the public function
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    text_replace() {
        _text_replace_sed_impl "$@"
    }
fi

# When executed directly: run with provided arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Minimal environment setup for standalone execution
    if [[ -z "${_TOOL_PATH[sed]:-}" ]]; then
        declare -A _TOOL_PATH=()
        declare -A _TOOL_VARIANT=()
        _TOOL_PATH[sed]="$(command -v sed 2>/dev/null || echo "sed")"
        # Simple variant detection
        if "${_TOOL_PATH[sed]}" --version 2>/dev/null | grep -q "GNU"; then
            _TOOL_VARIANT[sed]="gnu"
        else
            _TOOL_VARIANT[sed]="bsd"
        fi
    fi
    
    _text_replace_sed_impl "$@"
fi
