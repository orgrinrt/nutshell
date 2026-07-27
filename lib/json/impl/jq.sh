#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/json/impl/jq.sh - JSON through jq
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# One of three interchangeable backends behind `lib/json.sh`, which dispatches
# on `_JSON_IMPL`. Nothing here is called directly; the module's public
# functions pick a backend and forward.
#
# Sourced by json.sh when jq is present. All available backends are loaded
# rather than only the selected one, so a caller (or a test) can move
# `_JSON_IMPL` and get the implementation it named.
# =============================================================================

nut_once || return 0

# `-c` and `-S` on everything that returns a document.
#
# Without `-c` jq formats, and python and perl print compact, so the same call
# returned different text depending on which tool was installed. `-S` sorts
# object keys, which is the only order all three can produce: perl hashes do
# not preserve insertion order and JSON::PP cannot invent one, so document
# order is not available across the set. Sorted is, and it is stable.

# jq implementation of json_get
_json_get_jq() {
    local json="${1:-}"
    local path="${2:-}"
    
    # Convert dot notation to jq path if needed
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    echo "$json" | "${_TOOL_PATH[jq]}" -c -S -r "$path" 2>/dev/null
}

# jq implementation of json_set
_json_set_jq() {
    local json="${1:-}"
    local path="${2:-}"
    local value="${3:-}"
    
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    # Determine if value is a string or other JSON type
    if [[ "$value" == "true" || "$value" == "false" || "$value" == "null" || \
          "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ || \
          "$value" == "["* || "$value" == "{"* ]]; then
        echo "$json" | "${_TOOL_PATH[jq]}" -c -S "$path = $value" 2>/dev/null
    else
        echo "$json" | "${_TOOL_PATH[jq]}" -c -S --arg v "$value" "$path = \$v" 2>/dev/null
    fi
}

# jq implementation of json_keys
_json_keys_jq() {
    local json="${1:-}"
    local path="${2:-.}"
    
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    echo "$json" | "${_TOOL_PATH[jq]}" -r "$path | keys[]" 2>/dev/null
}

# jq implementation of json_valid
_json_valid_jq() {
    local json="${1:-}"
    echo "$json" | "${_TOOL_PATH[jq]}" -e . >/dev/null 2>&1
}

# jq implementation of json_pretty
_json_pretty_jq() {
    local json="${1:-}"
    echo "$json" | "${_TOOL_PATH[jq]}" -S '.' 2>/dev/null
}

# jq implementation of json_compact
_json_compact_jq() {
    local json="${1:-}"
    echo "$json" | "${_TOOL_PATH[jq]}" -c -S '.' 2>/dev/null
}

# jq implementation of json_type
_json_type_jq() {
    local json="${1:-}"
    local path="${2:-.}"
    
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    echo "$json" | "${_TOOL_PATH[jq]}" -r "$path | type" 2>/dev/null
}

# jq implementation of json_length
_json_length_jq() {
    local json="${1:-}"
    local path="${2:-.}"
    
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    echo "$json" | "${_TOOL_PATH[jq]}" -r "$path | length" 2>/dev/null
}

# `del` printed its result formatted while python and perl printed it
# compact, so one call returned different text depending on which tool
# happened to be installed. `-c`, matching every other operation here.

_json_merge_jq() {
    local json1="$1" json2="$2"
        echo "$json1" | "${_TOOL_PATH[jq]}" -c -S ". * $json2" 2>/dev/null
}

_json_delete_jq() {
    local json="$1" path="$2"
        echo "$json" | "${_TOOL_PATH[jq]}" -c -S "del($path)" 2>/dev/null
}
