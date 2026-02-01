#!/usr/bin/env bash
# =============================================================================
# nutshell/core/string.sh - String manipulation primitives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): No dependencies on other modules
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_STRING_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_STRING_SH=1

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Convert string to lowercase
# Usage: str_lower "HELLO" -> "hello"
str_lower() {
    local str="${1:-}"
    echo "${str,,}"
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Convert string to uppercase
# Usage: str_upper "hello" -> "HELLO"
str_upper() {
    local str="${1:-}"
    echo "${str^^}"
}

# @@PUBLIC_API@@
# Trim whitespace from both ends
# Usage: str_trim "  hello  " -> "hello"
str_trim() {
    local str="${1:-}"
    # Trim leading whitespace
    str="${str#"${str%%[![:space:]]*}"}"
    # Trim trailing whitespace
    str="${str%"${str##*[![:space:]]}"}"
    echo "$str"
}

# @@PUBLIC_API@@
# Trim whitespace from left side
# Usage: str_ltrim "  hello" -> "hello"
str_ltrim() {
    local str="${1:-}"
    str="${str#"${str%%[![:space:]]*}"}"
    echo "$str"
}

# @@PUBLIC_API@@
# Trim whitespace from right side
# Usage: str_rtrim "hello  " -> "hello"
str_rtrim() {
    local str="${1:-}"
    str="${str%"${str##*[![:space:]]}"}"
    echo "$str"
}

# @@PUBLIC_API@@
# Replace all occurrences of a substring
# Usage: str_replace "hello world" "world" "bash" -> "hello bash"
str_replace() {
    local str="${1:-}"
    local from="${2:-}"
    local to="${3:-}"
    
    [[ -z "$from" ]] && { echo "$str"; return 0; }
    echo "${str//$from/$to}"
}

# @@PUBLIC_API@@
# Check if string contains substring
# Usage: str_contains "hello world" "world" -> returns 0 (true)
str_contains() {
    local str="${1:-}"
    local substr="${2:-}"
    
    [[ -z "$substr" ]] && return 0  # Empty substring always matches
    [[ "$str" == *"$substr"* ]]
}

# @@PUBLIC_API@@
# Check if string starts with prefix
# Usage: str_starts_with "hello world" "hello" -> returns 0 (true)
str_starts_with() {
    local str="${1:-}"
    local prefix="${2:-}"
    
    [[ -z "$prefix" ]] && return 0
    [[ "$str" == "$prefix"* ]]
}

# @@PUBLIC_API@@
# Check if string ends with suffix
# Usage: str_ends_with "hello world" "world" -> returns 0 (true)
str_ends_with() {
    local str="${1:-}"
    local suffix="${2:-}"
    
    [[ -z "$suffix" ]] && return 0
    [[ "$str" == *"$suffix" ]]
}

# @@PUBLIC_API@@
# Split string by delimiter into array
# Usage: str_split ":" "a:b:c" arr -> arr=("a" "b" "c")
str_split() {
    local delim="${1:-}"
    local str="${2:-}"
    local -n _arr="${3:-_str_split_result}"
    
    _arr=()
    [[ -z "$str" ]] && return 0
    
    if [[ -z "$delim" ]]; then
        _arr=("$str")
        return 0
    fi
    
    local IFS="$delim"
    read -ra _arr <<< "$str"
}

# @@PUBLIC_API@@
# Join array elements with delimiter
# Usage: str_join "," "a" "b" "c" -> "a,b,c"
str_join() {
    local delim="${1:-}"
    shift
    
    local result=""
    local first=true
    
    for item in "$@"; do
        if $first; then
            result="$item"
            first=false
        else
            result="${result}${delim}${item}"
        fi
    done
    
    echo "$result"
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Get string length
# Usage: str_length "hello" -> 5
str_length() {
    local str="${1:-}"
    echo "${#str}"
}

# @@PUBLIC_API@@
# Extract substring
# Usage: str_substr "hello world" 0 5 -> "hello"
str_substr() {
    local str="${1:-}"
    local start="${2:-0}"
    local length="${3:-}"
    
    if [[ -n "$length" ]]; then
        echo "${str:$start:$length}"
    else
        echo "${str:$start}"
    fi
}

# @@PUBLIC_API@@
# Repeat string N times
# Usage: str_repeat "-" 5 -> "-----"
str_repeat() {
    local str="${1:-}"
    local count="${2:-1}"
    
    [[ $count -le 0 ]] && return 0
    
    local result=""
    for ((i=0; i<count; i++)); do
        result="${result}${str}"
    done
    echo "$result"
}
