#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/array.sh - Array manipulation primitives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): No dependencies on other modules
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_ARRAY_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_ARRAY_SH=1

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Check if array contains element
# Usage: arr_contains "needle" "${haystack[@]}" -> returns 0 (true) or 1 (false)
arr_contains() {
    local needle="${1:-}"
    shift
    
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

# @@PUBLIC_API@@
# Find index of element in array (returns 255 if not found)
# Usage: arr_index "needle" "${haystack[@]}" -> prints index or 255
arr_index() {
    local needle="${1:-}"
    shift
    
    local i=0
    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && { echo "$i"; return 0; }
        ((i++))
    done
    echo "255"
    return 1
}

# @@PUBLIC_API@@
# Remove duplicates from array (preserves order)
# Usage: arr_unique arr
arr_unique() {
    local -n _arr="$1"
    local -A seen=()
    local result=()
    
    local item
    for item in "${_arr[@]}"; do
        if [[ -z "${seen[$item]:-}" ]]; then
            seen[$item]=1
            result+=("$item")
        fi
    done
    
    _arr=("${result[@]}")
}

# @@PUBLIC_API@@
# Reverse array in place
# Usage: arr_reverse arr
arr_reverse() {
    local -n _arr="$1"
    local len=${#_arr[@]}
    
    [[ $len -le 1 ]] && return 0
    
    local i j temp
    for ((i=0, j=len-1; i<j; i++, j--)); do
        temp="${_arr[$i]}"
        _arr[$i]="${_arr[$j]}"
        _arr[$j]="$temp"
    done
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Get array length
# Usage: arr_length "${arr[@]}" -> prints count
arr_length() {
    echo "$#"
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Check if array is empty
# Usage: arr_is_empty "${arr[@]}" -> returns 0 (true) if empty
arr_is_empty() {
    [[ $# -eq 0 ]]
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Get first element of array
# Usage: arr_first "${arr[@]}" -> prints first element
arr_first() {
    [[ $# -gt 0 ]] && echo "$1"
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Get last element of array
# Usage: arr_last "${arr[@]}" -> prints last element
arr_last() {
    [[ $# -gt 0 ]] && echo "${!#}"
}

# @@PUBLIC_API@@
# Sort array in place (lexicographic)
# Usage: arr_sort arr
arr_sort() {
    local -n _arr="$1"
    local -a sorted
    
    [[ ${#_arr[@]} -le 1 ]] && return 0
    
    readarray -t sorted < <(printf '%s\n' "${_arr[@]}" | sort)
    _arr=("${sorted[@]}")
}

# @@PUBLIC_API@@
# Filter array by pattern
# Usage: arr_filter "pattern" "${arr[@]}" -> prints matching elements
arr_filter() {
    local pattern="${1:-}"
    shift
    
    local item
    for item in "$@"; do
        [[ "$item" == $pattern ]] && echo "$item"
    done
}
