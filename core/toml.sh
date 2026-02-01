#!/usr/bin/env bash
# =============================================================================
# nutshell/core/toml.sh - TOML parsing
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on fs.sh, string.sh, validate.sh
#
# Pure TOML parsing functions. No caching, no config semantics.
# Handles basic TOML: key = "value", [sections], arrays, booleans.
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_TOML_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_TOML_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

_NUTSHELL_TOML_DIR="${BASH_SOURCE[0]%/*}"
source "${_NUTSHELL_TOML_DIR}/fs.sh"
source "${_NUTSHELL_TOML_DIR}/string.sh"
source "${_NUTSHELL_TOML_DIR}/validate.sh"

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

# Remove inline comments and trim whitespace from a line
_toml_clean_line() {
    local line="$1"
    # Remove inline comments (# not inside quotes - simplified)
    line="${line%%#*}"
    str_trim "$line"
}

# Extract value, handling quotes
_toml_extract_value() {
    local raw="$1"
    raw="$(str_trim "$raw")"
    
    # Double-quoted string
    if [[ "$raw" =~ ^\"(.*)\"$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # Single-quoted string (literal)
    if [[ "$raw" =~ ^\'(.*)\'$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # Unquoted value (number, boolean, etc.)
    echo "$raw"
}

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Get a value from a TOML file
# Usage: toml_get "file.toml" "key" -> prints value
# Usage: toml_get "file.toml" "section.key" -> prints value from [section]
toml_get() {
    local file="${1:-}"
    local key="${2:-}"
    
    [[ ! -f "$file" ]] && return 1
    [[ -z "$key" ]] && return 1
    
    local section=""
    local search_key="$key"
    
    # Check if key has section prefix (section.key)
    if [[ "$key" == *.* ]]; then
        section="${key%%.*}"
        search_key="${key#*.}"
    fi
    
    local in_section=0
    local current_section=""
    local line clean_line
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        clean_line="$(_toml_clean_line "$line")"
        [[ -z "$clean_line" ]] && continue
        
        # Section header
        if [[ "$clean_line" =~ ^\[([^\]]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            if [[ -z "$section" ]]; then
                in_section=0
            elif [[ "$current_section" == "$section" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi
        
        # Skip if we need a section but aren't in it
        if [[ -n "$section" && $in_section -eq 0 ]]; then
            continue
        fi
        
        # Skip if we don't want a section but are in one
        if [[ -z "$section" && -n "$current_section" ]]; then
            continue
        fi
        
        # Key = value
        if [[ "$clean_line" =~ ^([^=]+)=(.*)$ ]]; then
            local k v
            k="$(str_trim "${BASH_REMATCH[1]}")"
            v="$(str_trim "${BASH_REMATCH[2]}")"
            
            if [[ "$k" == "$search_key" ]]; then
                _toml_extract_value "$v"
                return 0
            fi
        fi
    done < "$file"
    
    return 1
}

# @@PUBLIC_API@@
# Get a value with a default if not found
# Usage: toml_get_or "file.toml" "key" "default"
toml_get_or() {
    local file="${1:-}"
    local key="${2:-}"
    local default="${3:-}"
    
    local value
    if value="$(toml_get "$file" "$key")"; then
        echo "$value"
    else
        echo "$default"
    fi
}

# @@PUBLIC_API@@
# Check if a key exists in a TOML file
# Usage: toml_has "file.toml" "key" -> returns 0 (true) or 1 (false)
toml_has() {
    local file="${1:-}"
    local key="${2:-}"
    
    toml_get "$file" "$key" >/dev/null 2>&1
}

# @@PUBLIC_API@@
# List all section names in a TOML file
# Usage: toml_sections "file.toml" -> prints section names, one per line
toml_sections() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && return 1
    
    local line clean_line
    while IFS= read -r line || [[ -n "$line" ]]; do
        clean_line="$(_toml_clean_line "$line")"
        if [[ "$clean_line" =~ ^\[([^\]]+)\]$ ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done < "$file"
}

# @@PUBLIC_API@@
# List all keys in a section (or root if no section specified)
# Usage: toml_keys "file.toml" [section]
toml_keys() {
    local file="${1:-}"
    local section="${2:-}"
    
    [[ ! -f "$file" ]] && return 1
    
    local in_section=0
    local current_section=""
    local line clean_line
    
    # If no section specified, we want root-level keys
    [[ -z "$section" ]] && in_section=1
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        clean_line="$(_toml_clean_line "$line")"
        [[ -z "$clean_line" ]] && continue
        
        # Section header
        if [[ "$clean_line" =~ ^\[([^\]]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            if [[ -z "$section" ]]; then
                in_section=0  # Stop reading root keys when we hit a section
            elif [[ "$current_section" == "$section" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi
        
        [[ $in_section -eq 0 ]] && continue
        
        # Key = value
        if [[ "$clean_line" =~ ^([^=]+)= ]]; then
            str_trim "${BASH_REMATCH[1]}"
        fi
    done < "$file"
}

# @@PUBLIC_API@@
# Parse a TOML array value into a bash array
# Usage: toml_array "file.toml" "key" arr
toml_array() {
    local file="${1:-}"
    local key="${2:-}"
    local -n _arr="${3:-_toml_array_result}"
    
    _arr=()
    
    local value
    value="$(toml_get "$file" "$key")" || return 1
    
    # Check if it's an array format: [ "a", "b", "c" ]
    if [[ "$value" =~ ^\[.*\]$ ]]; then
        # Remove brackets
        value="${value#[}"
        value="${value%]}"
        value="$(str_trim "$value")"
        
        # Split by comma, handling quoted strings
        local in_quotes=0
        local current=""
        local char
        local i
        
        for ((i=0; i<${#value}; i++)); do
            char="${value:$i:1}"
            
            if [[ "$char" == '"' ]]; then
                ((in_quotes = 1 - in_quotes))
            elif [[ "$char" == ',' && $in_quotes -eq 0 ]]; then
                current="$(str_trim "$current")"
                [[ -n "$current" ]] && _arr+=("$(_toml_extract_value "$current")")
                current=""
                continue
            fi
            
            current+="$char"
        done
        
        # Don't forget the last element
        current="$(str_trim "$current")"
        [[ -n "$current" ]] && _arr+=("$(_toml_extract_value "$current")")
    else
        # Single value, treat as single-element array
        _arr+=("$value")
    fi
}

# @@PUBLIC_API@@
# Check if a TOML value is true (handles various boolean representations)
# Usage: toml_is_true "file.toml" "key" -> returns 0 (true) or 1 (false)
toml_is_true() {
    local file="${1:-}"
    local key="${2:-}"
    
    local value
    value="$(toml_get "$file" "$key")" || return 1
    
    is_truthy "$value"
}

# @@PUBLIC_API@@
# Get all key=value pairs from a section as "key=value" lines
# Usage: toml_section_pairs "file.toml" "section"
toml_section_pairs() {
    local file="${1:-}"
    local section="${2:-}"
    
    [[ ! -f "$file" ]] && return 1
    [[ -z "$section" ]] && return 1
    
    local in_section=0
    local current_section=""
    local line clean_line
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        clean_line="$(_toml_clean_line "$line")"
        [[ -z "$clean_line" ]] && continue
        
        # Section header
        if [[ "$clean_line" =~ ^\[([^\]]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            if [[ "$current_section" == "$section" ]]; then
                in_section=1
            else
                [[ $in_section -eq 1 ]] && break  # We've left our section
                in_section=0
            fi
            continue
        fi
        
        [[ $in_section -eq 0 ]] && continue
        
        # Key = value
        if [[ "$clean_line" =~ ^([^=]+)=(.*)$ ]]; then
            local k v
            k="$(str_trim "${BASH_REMATCH[1]}")"
            v="$(_toml_extract_value "$(str_trim "${BASH_REMATCH[2]}")")"
            echo "${k}=${v}"
        fi
    done < "$file"
}
