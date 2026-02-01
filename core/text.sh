#!/usr/bin/env bash
# =============================================================================
# nutshell/core/text.sh - Text processing primitives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on deps.sh for tool detection
#
# This module provides text processing functions. Functions that require
# external tools (sed, grep, awk, perl) use lazy-init stubs that, on first
# call, select and source the appropriate implementation. Subsequent calls
# go directly to the implementation with no overhead.
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_TEXT_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_TEXT_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

_NUTSHELL_TEXT_DIR="${BASH_SOURCE[0]%/*}"
# Handle case when sourced from same directory (BASH_SOURCE[0] has no path component)
[[ "$_NUTSHELL_TEXT_DIR" == "${BASH_SOURCE[0]}" ]] && _NUTSHELL_TEXT_DIR="."
source "${_NUTSHELL_TEXT_DIR}/deps.sh"

# Path to impl directory
readonly _TEXT_IMPL_DIR="${_NUTSHELL_TEXT_DIR}/text/impl"

# -----------------------------------------------------------------------------
# Module status
# -----------------------------------------------------------------------------

_TEXT_READY=0
_TEXT_ERROR=""

# Check that we have at least one usable tool for text operations
if deps_has_any "sed" "perl" "awk"; then
    _TEXT_READY=1
else
    _TEXT_ERROR="No text processing tool available (need sed, perl, or awk)"
fi

# -----------------------------------------------------------------------------
# Line operations (pure bash + standard tools; no impl switching needed)
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Count lines in file
# Usage: text_line_count "file" -> "42"
text_line_count() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && { echo "0"; return 1; }
    wc -l < "$file" | tr -d ' '
}

# @@PUBLIC_API@@
# Count words in file
# Usage: text_word_count "file" -> "123"
text_word_count() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && { echo "0"; return 1; }
    wc -w < "$file" | tr -d ' '
}

# @@PUBLIC_API@@
# Get first N lines of file
# Usage: text_head "file" [n=10]
text_head() {
    local file="${1:-}"
    local n="${2:-10}"
    [[ ! -f "$file" ]] && return 1
    head -n "$n" "$file"
}

# @@PUBLIC_API@@
# Get last N lines of file
# Usage: text_tail "file" [n=10]
text_tail() {
    local file="${1:-}"
    local n="${2:-10}"
    [[ ! -f "$file" ]] && return 1
    tail -n "$n" "$file"
}

# @@PUBLIC_API@@
# Get specific line from file
# Usage: text_line "file" 5 -> prints line 5
text_line() {
    local file="${1:-}"
    local num="${2:-1}"
    [[ ! -f "$file" ]] && return 1
    
    # Use sed if available, otherwise awk
    if deps_has "sed"; then
        "${_TOOL_PATH[sed]}" -n "${num}p" "$file"
    elif deps_has "awk"; then
        "${_TOOL_PATH[awk]}" "NR==${num}" "$file"
    else
        # Pure bash fallback (slow for large files)
        local i=0
        while IFS= read -r line; do
            ((i++))
            if [[ $i -eq $num ]]; then
                echo "$line"
                return 0
            fi
        done < "$file"
        return 1
    fi
}

# @@PUBLIC_API@@
# Get range of lines from file
# Usage: text_lines "file" 5 10 -> prints lines 5-10
text_lines() {
    local file="${1:-}"
    local start="${2:-1}"
    local end="${3:-}"
    [[ ! -f "$file" ]] && return 1
    
    if deps_has "sed"; then
        if [[ -n "$end" ]]; then
            "${_TOOL_PATH[sed]}" -n "${start},${end}p" "$file"
        else
            "${_TOOL_PATH[sed]}" -n "${start}p" "$file"
        fi
    elif deps_has "awk"; then
        if [[ -n "$end" ]]; then
            "${_TOOL_PATH[awk]}" "NR>=${start} && NR<=${end}" "$file"
        else
            "${_TOOL_PATH[awk]}" "NR==${start}" "$file"
        fi
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Pattern matching - LAZY INIT STUBS
# These stubs select and source the best implementation on first call
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Find lines matching pattern
# Usage: text_grep "pattern" "file" -> prints matching lines
text_grep() {
    # First call: decide which implementation to use
    if deps_has "grep"; then
        source "${_TEXT_IMPL_DIR}/grep_match.sh"
    elif deps_has "perl"; then
        source "${_TEXT_IMPL_DIR}/perl_match.sh"
    else
        # No tool available; define a failing function
        text_grep() {
            echo "[ERROR] text_grep: no matching tool available (need grep or perl)" >&2
            return 1
        }
    fi
    
    # Call the now-replaced function
    text_grep "$@"
}

# @@PUBLIC_API@@
# Check if file contains pattern
# Usage: text_contains "pattern" "file" -> returns 0 (true) or 1 (false)
text_contains() {
    # First call: decide which implementation to use
    if deps_has "grep"; then
        source "${_TEXT_IMPL_DIR}/grep_match.sh"
    elif deps_has "perl"; then
        source "${_TEXT_IMPL_DIR}/perl_match.sh"
    else
        text_contains() {
            echo "[ERROR] text_contains: no matching tool available" >&2
            return 1
        }
    fi
    
    text_contains "$@"
}

# @@PUBLIC_API@@
# Count occurrences of pattern in file
# Usage: text_count_matches "pattern" "file" -> "5"
text_count_matches() {
    # First call: decide which implementation to use
    if deps_has "grep"; then
        source "${_TEXT_IMPL_DIR}/grep_match.sh"
    elif deps_has "perl"; then
        source "${_TEXT_IMPL_DIR}/perl_match.sh"
    else
        text_count_matches() {
            echo "0"
            return 1
        }
    fi
    
    text_count_matches "$@"
}

# -----------------------------------------------------------------------------
# Text manipulation - LAZY INIT STUBS
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Replace pattern in file (in-place)
# Usage: text_replace "pattern" "replacement" "file"
text_replace() {
    # First call: decide which implementation to use based on available tools
    # and their variants
    local impl=""
    
    if deps_has "sed"; then
        # sed is preferred for simple replacements
        impl="sed_replace.sh"
    elif deps_has "perl"; then
        # perl works consistently across platforms
        impl="perl_replace.sh"
    elif deps_has "awk"; then
        # awk as last resort (requires temp file)
        impl="awk_replace.sh"
    fi
    
    if [[ -n "$impl" ]]; then
        source "${_TEXT_IMPL_DIR}/${impl}"
    else
        # No tool available
        text_replace() {
            echo "[ERROR] text_replace: no tool available (need sed, perl, or awk)" >&2
            return 1
        }
    fi
    
    # Call the now-replaced function
    text_replace "$@"
}

# -----------------------------------------------------------------------------
# Simple operations (don't need impl switching)
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Append line to file
# Usage: text_append "line" "file"
text_append() {
    local line="${1:-}"
    local file="${2:-}"
    [[ -z "$file" ]] && return 1
    echo "$line" >> "$file"
}

# @@PUBLIC_API@@
# Prepend line to file
# Usage: text_prepend "line" "file"
text_prepend() {
    local line="${1:-}"
    local file="${2:-}"
    [[ ! -f "$file" ]] && return 1
    
    local temp
    if deps_has "mktemp"; then
        temp="$("${_TOOL_PATH[mktemp]}")"
    else
        temp="/tmp/text_prepend.$$"
    fi
    
    echo "$line" > "$temp"
    cat "$file" >> "$temp"
    mv "$temp" "$file"
}

# @@PUBLIC_API@@
# Extract text between two markers
# Usage: text_between "file" "START" "END" -> prints text between markers
text_between() {
    local file="${1:-}"
    local start="${2:-}"
    local end="${3:-}"
    [[ ! -f "$file" || -z "$start" || -z "$end" ]] && return 1
    
    if deps_has "sed"; then
        "${_TOOL_PATH[sed]}" -n "/${start}/,/${end}/p" "$file" | "${_TOOL_PATH[sed]}" '1d;$d'
    elif deps_has "awk"; then
        "${_TOOL_PATH[awk]}" "/${start}/,/${end}/" "$file" | "${_TOOL_PATH[awk]}" 'NR>1 { print prev } { prev=$0 }'
    elif deps_has "perl"; then
        "${_TOOL_PATH[perl]}" -ne "print if /${start}/../${end}/" "$file" | "${_TOOL_PATH[perl]}" -ne 'print unless $. == 1 || eof'
    else
        return 1
    fi
}

# @@PUBLIC_API@@
# Remove blank lines from file content
# Usage: text_remove_blank "file" -> prints non-blank lines
text_remove_blank() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && return 1
    
    if deps_has "grep"; then
        "${_TOOL_PATH[grep]}" -v '^[[:space:]]*$' "$file" || true
    elif deps_has "sed"; then
        "${_TOOL_PATH[sed]}" '/^[[:space:]]*$/d' "$file"
    elif deps_has "awk"; then
        "${_TOOL_PATH[awk]}" 'NF' "$file"
    else
        # Pure bash fallback
        while IFS= read -r line; do
            [[ -n "${line// /}" ]] && echo "$line"
        done < "$file"
    fi
}

# @@PUBLIC_API@@
# Remove comment lines (starting with #)
# Usage: text_remove_comments "file" -> prints non-comment lines
text_remove_comments() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && return 1
    
    if deps_has "grep"; then
        "${_TOOL_PATH[grep]}" -v '^[[:space:]]*#' "$file" | "${_TOOL_PATH[grep]}" -v '^[[:space:]]*$' || true
    elif deps_has "sed"; then
        "${_TOOL_PATH[sed]}" -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$file"
    elif deps_has "awk"; then
        "${_TOOL_PATH[awk]}" '!/^[[:space:]]*#/ && NF' "$file"
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Module readiness check
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Check if text module is ready to use
# Usage: text_ready -> returns 0 if ready, 1 if not
text_ready() {
    [[ "$_TEXT_READY" == "1" ]]
}

# @@PUBLIC_API@@
# Get text module error message (if not ready)
# Usage: text_error -> prints error message
text_error() {
    echo "$_TEXT_ERROR"
}
