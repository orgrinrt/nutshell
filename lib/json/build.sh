#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/json/build.sh - building JSON from values, with no tool
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# `json_object` and `json_array`: text assembled and escaped in the shell, so
# they work on a machine with none of jq, python and perl. Loaded by
# `lib/json.sh`, which is where a caller gets them from.

[ -n "${_NUTSHELL_JSON_BUILD_SH:-}" ] && return 0
_NUTSHELL_JSON_BUILD_SH=1

use string

# A newline and a tab as themselves. There is no `$'\n'` here to write one
# inline with, and the trailing `.` is because command substitution strips the
# trailing newline, which is the character being asked for.
_JSON_NL="$(printf '\n.')"; _JSON_NL="${_JSON_NL%.}"
_JSON_TAB="$(printf '\t.')"; _JSON_TAB="${_JSON_TAB%.}"

# -----------------------------------------------------------------------------

#[pub]
# Create a simple JSON object from key-value pairs
# Usage: json_object "key1" "value1" "key2" "value2" -> '{"key1":"value1","key2":"value2"}'
# Returns: JSON object
json_object() {
    local result="{"
    local first=1

    while [ $# -ge 2 ]; do
        local key="$1"
        local value="$2"
        shift 2

        [ "$first" -eq 0 ] && result="${result},"
        first=0

        # Escape special characters in value
        # Backslash first. Any other order escapes the backslashes it adds.
        str_replace "$value" '\' '\\' value
        str_replace "$value" '"' '\"' value
        str_replace "$value" "$_JSON_NL" '\n' value
        str_replace "$value" "$_JSON_TAB" '\t' value

        result="${result}""\"${key}\":\"${value}\""
    done

    result="${result}""}"
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
        [ "$first" -eq 0 ] && result="${result},"
        first=0

        # Escape special characters
        # Backslash first. Any other order escapes the backslashes it adds.
        str_replace "$value" '\' '\\' value
        str_replace "$value" '"' '\"' value
        str_replace "$value" "$_JSON_NL" '\n' value
        str_replace "$value" "$_JSON_TAB" '\t' value

        result="${result}""\"${value}\""
    done

    result="${result}""]"
    echo "$result"
}

