#!/usr/bin/env bash
# =============================================================================
# nutshell/core/json.sh - JSON parsing and manipulation
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on deps.sh for tool detection
#
# Provides JSON parsing and manipulation functions. Uses lazy-init stubs to
# select the best available tool (jq > python > perl > pure bash fallback).
#
# Object keys come back sorted, and documents come back compact. Not a
# preference: a perl hash has no order and its iteration order is randomised
# per process, so sorted is the only order all three backends can produce, and
# `json_pretty` is where formatting lives. Without this the same call returned
# different text depending on which tool happened to be installed, and on perl
# a different order on every run.
#
# Features:
#   - Get values by path (dot notation or jq syntax)
#   - Set/modify values
#   - Array operations
#   - Validation
#   - Pretty printing
# =============================================================================

# Prevent multiple inclusion
nut_once || return 0

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

# Declared, not sourced by path. A hand-rolled `source` loads the module and
# hides it from the module-contract check, which reads `use` lines, so the
# dependency was real and unrecorded at once.
use deps

# -----------------------------------------------------------------------------
# Module Status
# -----------------------------------------------------------------------------

_JSON_READY=0
_JSON_ERROR=""
_JSON_IMPL=""

# Check for available JSON tools
if deps_has "jq"; then
    _JSON_READY=1
    _JSON_IMPL="jq"
elif deps_has "python3" || deps_has "python"; then
    _JSON_READY=1
    _JSON_IMPL="python"
elif deps_has "perl"; then
    _JSON_READY=1
    _JSON_IMPL="perl"
else
    _JSON_ERROR="No JSON tool available (need jq, python, or perl)"
fi

# -----------------------------------------------------------------------------
# Backends
# -----------------------------------------------------------------------------
#
# Three interchangeable implementations of the same eight operations, one per
# tool, in `json/impl/`. They lived here and made this file 940 lines, of which
# the public surface was the last fifth.
#
# Every backend whose tool is present is loaded, not only the selected one.
# Loading one would save little (they are function definitions) and would make
# `_JSON_IMPL` a decision taken once at load rather than a value the dispatch
# reads, which is what lets a caller move it and lets the tests exercise all
# three rather than whichever the machine happened to pick.
readonly _JSON_IMPL_DIR="${BASH_SOURCE[0]%/*}/json/impl"

deps_has jq && source "${_JSON_IMPL_DIR}/jq.sh"
{ deps_has python3 || deps_has python; } && source "${_JSON_IMPL_DIR}/python.sh"
deps_has perl && source "${_JSON_IMPL_DIR}/perl.sh"


# -----------------------------------------------------------------------------
# Public API - Core Functions
# -----------------------------------------------------------------------------

#[pub]
# Get a value from JSON by path
# Usage: json_get '{"foo":"bar"}' "foo" -> "bar"
# Usage: json_get '{"a":{"b":1}}' "a.b" -> "1"
# Usage: json_get '[1,2,3]' "1" -> "2"
# Returns: The value at the path, or empty if not found
json_get() {
    local json="${1:-}"
    local path="${2:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_get_jq "$json" "$path" ;;
        python) _json_get_python "$json" "$path" ;;
        perl)   _json_get_perl "$json" "$path" ;;
    esac
}

#[pub]
# Set a value in JSON by path
# Usage: json_set '{"foo":"bar"}' "foo" "baz" -> '{"foo":"baz"}'
# Usage: json_set '{}' "new.key" "value" -> '{"new":{"key":"value"}}'
# Returns: The modified JSON
json_set() {
    local json="${1:-}"
    local path="${2:-}"
    local value="${3:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_set_jq "$json" "$path" "$value" ;;
        python) _json_set_python "$json" "$path" "$value" ;;
        perl)   _json_set_perl "$json" "$path" "$value" ;;
    esac
}

#[pub]
# Get all keys at a path in JSON
# Usage: json_keys '{"a":1,"b":2}' -> prints "a" and "b" on separate lines
# Usage: json_keys '{"x":{"y":1}}' "x" -> prints "y"
# Returns: Keys, one per line
json_keys() {
    local json="${1:-}"
    local path="${2:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_keys_jq "$json" "$path" ;;
        python) _json_keys_python "$json" "$path" ;;
        perl)   _json_keys_perl "$json" "$path" ;;
    esac
}

#[pub]
# Check if JSON is valid
# Usage: json_valid '{"foo":"bar"}' -> returns 0 (valid)
# Usage: json_valid 'not json' -> returns 1 (invalid)
# Returns: 0 if valid, 1 if invalid
json_valid() {
    local json="${1:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && return 1
    
    case "$_JSON_IMPL" in
        jq)     _json_valid_jq "$json" ;;
        python) _json_valid_python "$json" ;;
        perl)   _json_valid_perl "$json" ;;
    esac
}

#[pub]
# Pretty print JSON with indentation
# Usage: json_pretty '{"a":1,"b":2}' -> prints formatted JSON
# Returns: Pretty-printed JSON
json_pretty() {
    local json="${1:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_pretty_jq "$json" ;;
        python) _json_pretty_python "$json" ;;
        perl)   _json_pretty_perl "$json" ;;
    esac
}

#[pub]
# Compact JSON (remove whitespace)
# Usage: json_compact '{ "a": 1, "b": 2 }' -> '{"a":1,"b":2}'
# Returns: Compact JSON on single line
json_compact() {
    local json="${1:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_compact_jq "$json" ;;
        python) _json_compact_python "$json" ;;
        perl)   _json_compact_perl "$json" ;;
    esac
}

#[pub]
# Get the type of a JSON value
# Usage: json_type '{"a":1}' -> "object"
# Usage: json_type '[1,2]' -> "array"
# Usage: json_type '"str"' -> "string"
# Usage: json_type '123' -> "number"
# Usage: json_type 'true' -> "boolean"
# Usage: json_type 'null' -> "null"
# Returns: "object", "array", "string", "number", "boolean", or "null"
json_type() {
    local json="${1:-}"
    local path="${2:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_type_jq "$json" "$path" ;;
        python) _json_type_python "$json" "$path" ;;
        perl)   _json_type_perl "$json" "$path" ;;
    esac
}

#[pub]
# Get the length of a JSON array or object
# Usage: json_length '[1,2,3]' -> "3"
# Usage: json_length '{"a":1,"b":2}' -> "2"
# Returns: Length as number
json_length() {
    local json="${1:-}"
    local path="${2:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_length_jq "$json" "$path" ;;
        python) _json_length_python "$json" "$path" ;;
        perl)   _json_length_perl "$json" "$path" ;;
    esac
}

# -----------------------------------------------------------------------------
# Public API - Convenience Functions
# -----------------------------------------------------------------------------

#[pub]
# Check if a path exists in JSON
# Usage: json_has '{"a":{"b":1}}' "a.b" -> returns 0 (exists)
# Usage: json_has '{"a":1}' "b" -> returns 1 (not found)
# Returns: 0 if path exists, 1 otherwise
json_has() {
    local json="${1:-}"
    local path="${2:-}"
    
    local result
    result=$(json_get "$json" "$path" 2>/dev/null)
    [[ -n "$result" && "$result" != "null" ]]
}

#[pub]
# Get value with default if not found
# Usage: json_get_or '{"a":1}' "b" "default" -> "default"
# Usage: json_get_or '{"a":1}' "a" "default" -> "1"
# Returns: Value at path or default
json_get_or() {
    local json="${1:-}"
    local path="${2:-}"
    local default="${3:-}"
    
    local result
    result=$(json_get "$json" "$path" 2>/dev/null)
    
    if [[ -n "$result" && "$result" != "null" ]]; then
        echo "$result"
    else
        echo "$default"
    fi
}

#[pub]
# Create a simple JSON object from key-value pairs
# Usage: json_object "key1" "value1" "key2" "value2" -> '{"key1":"value1","key2":"value2"}'
# Returns: JSON object
json_object() {
    local result="{"
    local first=1
    
    while [[ $# -ge 2 ]]; do
        local key="$1"
        local value="$2"
        shift 2
        
        [[ $first -eq 0 ]] && result+=","
        first=0
        
        # Escape special characters in value
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        value="${value//$'\n'/\\n}"
        value="${value//$'\t'/\\t}"
        
        result+="\"${key}\":\"${value}\""
    done
    
    result+="}"
    echo "$result"
}

#[pub]
# Create a JSON array from values
# Usage: json_array "a" "b" "c" -> '["a","b","c"]'
# Returns: JSON array
json_array() {
    local result="["
    local first=1
    
    for value in "$@"; do
        [[ $first -eq 0 ]] && result+=","
        first=0
        
        # Escape special characters
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        value="${value//$'\n'/\\n}"
        value="${value//$'\t'/\\t}"
        
        result+="\"${value}\""
    done
    
    result+="]"
    echo "$result"
}

#[pub]
# Merge two JSON objects (second overwrites first for conflicts)
# Usage: json_merge '{"a":1}' '{"b":2}' -> '{"a":1,"b":2}'
# Returns: Merged JSON object
json_merge() {
    local json1="${1:-\{\}}"
    local json2="${2:-\{\}}"

    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }

    case "$_JSON_IMPL" in
        jq)     _json_merge_jq "$json1" "$json2" ;;
        python) _json_merge_python "$json1" "$json2" ;;
        perl)   _json_merge_perl "$json1" "$json2" ;;
    esac
}

#[pub]
# Delete a key from JSON
# Usage: json_delete '{"a":1,"b":2}' "a" -> '{"b":2}'
# Returns: JSON with key removed
json_delete() {
    local json="${1:-}"
    local path="${2:-}"

    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }

    [[ "$path" != "."* ]] && path=".${path}"

    case "$_JSON_IMPL" in
        jq)     _json_delete_jq "$json" "$path" ;;
        python) _json_delete_python "$json" "$path" ;;
        perl)   _json_delete_perl "$json" "$path" ;;
    esac
}

#[pub]
# Read JSON from a file
# Usage: json_read "/path/to/file.json" -> prints JSON content
# Returns: JSON content of file
json_read() {
    local file="${1:-}"
    
    [[ ! -f "$file" ]] && { echo "File not found: $file" >&2; return 1; }
    
    cat "$file"
}

#[pub]
# Write JSON to a file (pretty printed)
# Usage: json_write '{"a":1}' "/path/to/file.json"
# Returns: 0 on success, 1 on failure
json_write() {
    local json="${1:-}"
    local file="${2:-}"
    
    [[ -z "$file" ]] && return 1
    
    json_pretty "$json" > "$file"
}

# -----------------------------------------------------------------------------
# Module Status Functions
# -----------------------------------------------------------------------------

#[pub]
# Check if JSON module is ready
# Usage: json_ready -> returns 0 if ready, 1 if not
json_ready() {
    [[ "$_JSON_READY" == "1" ]]
}

#[pub]
# Get JSON module error (if not ready)
# Usage: json_error -> prints error message
json_error() {
    echo "$_JSON_ERROR"
}

#[pub]
# Get which JSON implementation is being used
# Usage: json_impl -> "jq" | "python" | "perl" | ""
json_impl() {
    echo "$_JSON_IMPL"
}
