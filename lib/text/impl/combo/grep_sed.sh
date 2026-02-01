#!/usr/bin/env bash
# =============================================================================
# nutshell/core/text/impl/combo/grep_sed.sh - grep+sed combo for text operations
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# This file provides a combined grep+sed implementation for operations that
# benefit from using both tools together:
#   - grep for fast filtering/matching
#   - sed for transformation
#
# Use case: When you need to find lines matching a pattern AND transform them,
# using grep to filter first can be faster than sed alone on large files.
#
# When sourced, it REPLACES the stubs in text.sh with combo implementations.
# Can also be executed directly for standalone use/testing.
# =============================================================================

# -----------------------------------------------------------------------------
# Internal implementation functions
# -----------------------------------------------------------------------------

# Search and replace only in lines matching a filter pattern
# This is more efficient than sed alone when only a subset of lines need changes
# Usage: _text_grep_sed_replace_impl "filter_pattern" "search" "replace" "file"
_text_grep_sed_filtered_replace_impl() {
    local filter="${1:-}"
    local search="${2:-}"
    local replace="${3:-}"
    local file="${4:-}"
    
    [[ -z "$filter" ]] && return 1
    [[ -z "$search" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    
    local grep_path="${_TOOL_PATH[grep]:-grep}"
    local sed_path="${_TOOL_PATH[sed]:-sed}"
    local variant="${_TOOL_VARIANT[sed]:-unknown}"
    
    # Create temp file
    local temp
    if [[ -n "${_TOOL_PATH[mktemp]:-}" ]]; then
        temp="$("${_TOOL_PATH[mktemp]}")"
    else
        temp="/tmp/grep_sed.$$"
    fi
    
    # Build sed in-place flag based on variant
    local sed_inplace
    if [[ "$variant" == "gnu" ]]; then
        sed_inplace="-i"
    else
        sed_inplace="-i ''"
    fi
    
    # Process: for each line, if it matches filter, apply sed replacement
    # This approach modifies in-place using line numbers
    local line_nums
    line_nums=$("$grep_path" -n "$filter" "$file" 2>/dev/null | cut -d: -f1)
    
    if [[ -n "$line_nums" ]]; then
        # Build sed command for specific lines
        local sed_cmd=""
        for num in $line_nums; do
            sed_cmd+="${num}s/${search}/${replace}/g;"
        done
        
        if [[ "$variant" == "gnu" ]]; then
            "$sed_path" -i "$sed_cmd" "$file"
        else
            "$sed_path" -i '' "$sed_cmd" "$file"
        fi
    fi
    
    return 0
}

# Extract and transform: grep matching lines, then apply sed transformation
# Usage: _text_grep_sed_extract_transform_impl "pattern" "search" "replace" "file"
# Returns: Transformed matching lines (does not modify file)
_text_grep_sed_extract_transform_impl() {
    local pattern="${1:-}"
    local search="${2:-}"
    local replace="${3:-}"
    local file="${4:-}"
    
    [[ -z "$pattern" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    
    local grep_path="${_TOOL_PATH[grep]:-grep}"
    local sed_path="${_TOOL_PATH[sed]:-sed}"
    
    # Grep first, pipe to sed
    "$grep_path" -E "$pattern" "$file" 2>/dev/null | "$sed_path" "s/${search}/${replace}/g"
}

# Count matches with context: find lines matching pattern, count occurrences of secondary pattern
# Usage: _text_grep_sed_count_in_matches_impl "filter_pattern" "count_pattern" "file"
_text_grep_sed_count_in_matches_impl() {
    local filter="${1:-}"
    local count_pattern="${2:-}"
    local file="${3:-}"
    
    [[ -z "$filter" ]] && { echo "0"; return 1; }
    [[ -z "$count_pattern" ]] && { echo "0"; return 1; }
    [[ ! -f "$file" ]] && { echo "0"; return 1; }
    
    local grep_path="${_TOOL_PATH[grep]:-grep}"
    local sed_path="${_TOOL_PATH[sed]:-sed}"
    
    # Grep lines matching filter, then count secondary pattern
    "$grep_path" -E "$filter" "$file" 2>/dev/null | "$grep_path" -c "$count_pattern" 2>/dev/null || echo "0"
}

# Standard text_replace but uses grep to check if pattern exists first
# Optimization: skip sed if pattern doesn't exist in file
# Usage: _text_replace_grep_sed_impl "pattern" "replacement" "file"
_text_replace_grep_sed_impl() {
    local pattern="${1:-}"
    local replacement="${2:-}"
    local file="${3:-}"
    
    [[ -z "$pattern" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    
    local grep_path="${_TOOL_PATH[grep]:-grep}"
    local sed_path="${_TOOL_PATH[sed]:-sed}"
    local variant="${_TOOL_VARIANT[sed]:-unknown}"
    
    # Quick check: does the pattern even exist?
    if ! "$grep_path" -qE "$pattern" "$file" 2>/dev/null; then
        # Pattern not found, nothing to replace
        return 0
    fi
    
    # Pattern exists, do the replacement
    if [[ "$variant" == "gnu" ]]; then
        "$sed_path" -i "s/${pattern}/${replacement}/g" "$file"
    else
        "$sed_path" -i '' "s/${pattern}/${replacement}/g" "$file"
    fi
}

# -----------------------------------------------------------------------------
# Public function replacements (when sourced)
# -----------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Replace text_replace with optimized grep+sed version
    text_replace() {
        _text_replace_grep_sed_impl "$@"
    }
    
    # Add new combo functions to the text module
    
    # @@PUBLIC_API@@
    # Replace pattern only in lines matching a filter
    # Usage: text_filtered_replace "filter_regex" "search" "replace" "file"
    text_filtered_replace() {
        _text_grep_sed_filtered_replace_impl "$@"
    }
    
    # @@PUBLIC_API@@
    # Extract matching lines and transform them (non-destructive)
    # Usage: text_extract_transform "pattern" "search" "replace" "file" -> prints transformed lines
    text_extract_transform() {
        _text_grep_sed_extract_transform_impl "$@"
    }
    
    # @@PUBLIC_API@@
    # Count occurrences of secondary pattern within lines matching primary pattern
    # Usage: text_count_in_matches "filter" "count_pattern" "file" -> "5"
    text_count_in_matches() {
        _text_grep_sed_count_in_matches_impl "$@"
    }
fi

# -----------------------------------------------------------------------------
# Standalone execution support
# -----------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Minimal environment setup for standalone execution
    if [[ -z "${_TOOL_PATH[grep]:-}" ]]; then
        declare -A _TOOL_PATH=()
        declare -A _TOOL_VARIANT=()
        _TOOL_PATH[grep]="$(command -v grep 2>/dev/null || echo "grep")"
        _TOOL_PATH[sed]="$(command -v sed 2>/dev/null || echo "sed")"
        _TOOL_PATH[mktemp]="$(command -v mktemp 2>/dev/null || echo "")"
        
        # Simple variant detection for sed
        if "${_TOOL_PATH[sed]}" --version 2>/dev/null | grep -q "GNU"; then
            _TOOL_VARIANT[sed]="gnu"
        else
            _TOOL_VARIANT[sed]="bsd"
        fi
    fi
    
    case "${1:-}" in
        --replace)
            shift
            _text_replace_grep_sed_impl "$@"
            ;;
        --filtered-replace)
            shift
            _text_grep_sed_filtered_replace_impl "$@"
            ;;
        --extract-transform)
            shift
            _text_grep_sed_extract_transform_impl "$@"
            ;;
        --count-in-matches)
            shift
            _text_grep_sed_count_in_matches_impl "$@"
            ;;
        --help|-h)
            echo "Usage: $0 <command> [args...]"
            echo ""
            echo "Commands:"
            echo "  --replace <pattern> <replacement> <file>"
            echo "      Replace pattern in file (skips if pattern not found)"
            echo ""
            echo "  --filtered-replace <filter> <search> <replace> <file>"
            echo "      Replace only in lines matching filter pattern"
            echo ""
            echo "  --extract-transform <pattern> <search> <replace> <file>"
            echo "      Print matching lines with transformation applied"
            echo ""
            echo "  --count-in-matches <filter> <count_pattern> <file>"
            echo "      Count secondary pattern in lines matching filter"
            echo ""
            echo "Examples:"
            echo "  $0 --replace 'foo' 'bar' myfile.txt"
            echo "  $0 --filtered-replace '^#' 'OLD' 'NEW' config.sh"
            echo "  $0 --extract-transform 'TODO' 'TODO' 'DONE' notes.txt"
            ;;
        *)
            echo "Usage: $0 [--replace|--filtered-replace|--extract-transform|--count-in-matches|--help] ..." >&2
            exit 1
            ;;
    esac
fi
