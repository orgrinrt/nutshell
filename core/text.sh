#!/usr/bin/env bash
# =============================================================================
# nutshell/core/text.sh - Text processing primitives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): No dependencies on other modules
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_TEXT_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_TEXT_SH=1

# -----------------------------------------------------------------------------
# Line operations
# -----------------------------------------------------------------------------

# Count lines in file
# Usage: text_line_count "file" -> "42"
text_line_count() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && { echo "0"; return 1; }
    wc -l < "$file" | tr -d ' '
}

# Count words in file
# Usage: text_word_count "file" -> "123"
text_word_count() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && { echo "0"; return 1; }
    wc -w < "$file" | tr -d ' '
}

# Get first N lines of file
# Usage: text_head "file" [n=10]
text_head() {
    local file="${1:-}"
    local n="${2:-10}"
    [[ ! -f "$file" ]] && return 1
    head -n "$n" "$file"
}

# Get last N lines of file
# Usage: text_tail "file" [n=10]
text_tail() {
    local file="${1:-}"
    local n="${2:-10}"
    [[ ! -f "$file" ]] && return 1
    tail -n "$n" "$file"
}

# Get specific line from file
# Usage: text_line "file" 5 -> prints line 5
text_line() {
    local file="${1:-}"
    local num="${2:-1}"
    [[ ! -f "$file" ]] && return 1
    sed -n "${num}p" "$file"
}

# Get range of lines from file
# Usage: text_lines "file" 5 10 -> prints lines 5-10
text_lines() {
    local file="${1:-}"
    local start="${2:-1}"
    local end="${3:-}"
    [[ ! -f "$file" ]] && return 1
    
    if [[ -n "$end" ]]; then
        sed -n "${start},${end}p" "$file"
    else
        sed -n "${start}p" "$file"
    fi
}

# -----------------------------------------------------------------------------
# Pattern matching
# -----------------------------------------------------------------------------

# Find lines matching pattern
# Usage: text_grep "pattern" "file" -> prints matching lines
text_grep() {
    local pattern="${1:-}"
    local file="${2:-}"
    [[ -z "$pattern" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    grep -E "$pattern" "$file" 2>/dev/null || true
}

# Check if file contains pattern
# Usage: text_contains "pattern" "file" -> returns 0 (true) or 1 (false)
text_contains() {
    local pattern="${1:-}"
    local file="${2:-}"
    [[ -z "$pattern" ]] && return 1
    [[ ! -f "$file" ]] && return 1
    grep -qE "$pattern" "$file" 2>/dev/null
}

# Count occurrences of pattern in file
# Usage: text_count_matches "pattern" "file" -> "5"
text_count_matches() {
    local pattern="${1:-}"
    local file="${2:-}"
    [[ -z "$pattern" ]] && { echo "0"; return 1; }
    [[ ! -f "$file" ]] && { echo "0"; return 1; }
    grep -cE "$pattern" "$file" 2>/dev/null || echo "0"
}

# -----------------------------------------------------------------------------
# Text manipulation
# -----------------------------------------------------------------------------

# Replace pattern in file (in-place)
# Usage: text_replace "pattern" "replacement" "file"
text_replace() {
    local pattern="${1:-}"
    local replacement="${2:-}"
    local file="${3:-}"
    [[ -z "$pattern" || ! -f "$file" ]] && return 1
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' "s/${pattern}/${replacement}/g" "$file"
    else
        sed -i "s/${pattern}/${replacement}/g" "$file"
    fi
}

# Append line to file
# Usage: text_append "line" "file"
text_append() {
    local line="${1:-}"
    local file="${2:-}"
    [[ -z "$file" ]] && return 1
    echo "$line" >> "$file"
}

# Prepend line to file
# Usage: text_prepend "line" "file"
text_prepend() {
    local line="${1:-}"
    local file="${2:-}"
    [[ ! -f "$file" ]] && return 1
    
    local temp
    temp=$(mktemp)
    echo "$line" > "$temp"
    cat "$file" >> "$temp"
    mv "$temp" "$file"
}

# Extract text between two markers
# Usage: text_between "file" "START" "END" -> prints text between markers
text_between() {
    local file="${1:-}"
    local start="${2:-}"
    local end="${3:-}"
    [[ ! -f "$file" || -z "$start" || -z "$end" ]] && return 1
    sed -n "/${start}/,/${end}/p" "$file" | sed '1d;$d'
}

# Remove blank lines from file content
# Usage: text_remove_blank "file" -> prints non-blank lines
text_remove_blank() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && return 1
    grep -v '^[[:space:]]*$' "$file" || true
}

# Remove comment lines (starting with #)
# Usage: text_remove_comments "file" -> prints non-comment lines
text_remove_comments() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && return 1
    grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$' || true
}
