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
#
# `-c` and `-S` on everything that returns a document. Without `-c` jq formats
# where python and perl print compact, and `-S` sorts object keys, which is the
# only order all three can produce: a perl hash does not preserve insertion
# order and JSON::PP cannot invent one.
# =============================================================================

nut_once || return 0

# _jq_path <dotted-path> -> a jq path expression
#
# Every function here used to build its own by putting a dot in front of the
# whole path, which is wrong for any segment that is a number: `.1` is not the
# second element of an array, it is the number 0.1, so `json_get '[10,20]' 1`
# answered `0.1`. Bracket form for both kinds, and a name is quoted so a key
# holding a dash or a space stays one segment.
_jq_path() {
    local dotted="${1:-}" expr="." seg
    [[ "$dotted" == .* ]] && dotted="${dotted#.}"
    [[ -z "$dotted" ]] && { printf '.'; return 0; }

    local IFS='.'
    for seg in $dotted; do
        [[ -z "$seg" ]] && continue
        if [[ "$seg" =~ ^[0-9]+$ ]]; then
            expr+="[${seg}]"
        else
            expr+="[\"${seg}\"]"
        fi
    done
    printf '%s' "$expr"
}

# _jq_present <json> <dotted-path> -> 0 when the path leads somewhere
#
# jq answers `null` both for a key that is absent and for one that is present
# and holds null, and both with a status of zero. A caller cannot tell those
# apart, and `json_get_or` has to.
_jq_present() {
    local json="$1" dotted="${2:-}" parent last answer
    [[ "$dotted" == .* ]] && dotted="${dotted#.}"
    [[ -z "$dotted" ]] && return 0

    last="${dotted##*.}"
    if [[ "$last" == "$dotted" ]]; then
        parent="."
    else
        parent="$(_jq_path "${dotted%.*}")"
    fi

    answer="$(printf '%s' "$json" | "${_TOOL_PATH[jq]}" -r \
        "${parent} | if type == \"object\" then has(\"${last}\")
         elif type == \"array\" then ((\"${last}\" | tonumber? // -1) as \$i
              | \$i >= 0 and \$i < length)
         else false end" 2>/dev/null)"
    [[ "$answer" == "true" ]]
}

_json_get_jq() {
    local json="${1:-}" path="${2:-}" expr

    _jq_present "$json" "$path" || return 1

    expr="$(_jq_path "$path")"
    printf '%s\n' "$json" | "${_TOOL_PATH[jq]}" -c -S -r "$expr" 2>/dev/null
}

_json_set_jq() {
    local json="${1:-}" path="${2:-}" value="${3:-}" expr
    expr="$(_jq_path "$path")"

    # Determine if value is a string or other JSON type
    if [[ "$value" == "true" || "$value" == "false" || "$value" == "null" || \
          "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ || \
          "$value" == "["* || "$value" == "{"* ]]; then
        printf '%s\n' "$json" | "${_TOOL_PATH[jq]}" -c -S "$expr = $value" 2>/dev/null
    else
        printf '%s\n' "$json" | "${_TOOL_PATH[jq]}" -c -S --arg v "$value" "$expr = \$v" 2>/dev/null
    fi
}

_json_keys_jq() {
    local json="${1:-}" path="${2:-}" expr
    expr="$(_jq_path "$path")"
    printf '%s\n' "$json" | "${_TOOL_PATH[jq]}" -r "$expr | if type == \"array\" then range(length) else keys[] end" 2>/dev/null
}

_json_valid_jq() {
    local json="${1:-}"
    printf '%s\n' "$json" | "${_TOOL_PATH[jq]}" -e . >/dev/null 2>&1
}

_json_pretty_jq() {
    local json="${1:-}"
    printf '%s\n' "$json" | "${_TOOL_PATH[jq]}" -S '.' 2>/dev/null
}

_json_compact_jq() {
    local json="${1:-}"
    printf '%s\n' "$json" | "${_TOOL_PATH[jq]}" -c -S '.' 2>/dev/null
}

_json_type_jq() {
    local json="${1:-}" path="${2:-}" expr
    _jq_present "$json" "$path" || return 1
    expr="$(_jq_path "$path")"
    printf '%s\n' "$json" | "${_TOOL_PATH[jq]}" -r "$expr | type" 2>/dev/null
}

_json_length_jq() {
    local json="${1:-}" path="${2:-}" expr
    _jq_present "$json" "$path" || return 1
    expr="$(_jq_path "$path")"
    printf '%s\n' "$json" | "${_TOOL_PATH[jq]}" -r "$expr | length" 2>/dev/null
}

# `*` recurses into objects where python's `update` and perl's slice assignment
# replace them, so one call built a different document depending on the tool.
# `+` is the shallow one: the right operand replaces a key rather than merging
# into it.
_json_merge_jq() {
    local json1="$1" json2="$2"
    printf '%s\n' "$json1" | "${_TOOL_PATH[jq]}" -c -S ". + $json2" 2>/dev/null
}

# `del` printed its result formatted while python and perl printed it compact.
_json_delete_jq() {
    local json="$1" path="$2" expr
    expr="$(_jq_path "$path")"
    printf '%s\n' "$json" | "${_TOOL_PATH[jq]}" -c -S "del($expr)" 2>/dev/null
}
