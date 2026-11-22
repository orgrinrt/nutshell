#!/usr/bin/env bash
# nutshell/toml/json.sh - TOML as JSON
# https://github.com/orgrinrt/nutshell
#
# Converting to another format is a job of its own, and it is the only part of
# the toml module that has to know what JSON looks like.

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE`
# and so needs bash. Under a POSIX shell it is not found, the
# `|| return 0` beside it fires on every load, and the module reports
# success having defined nothing.
[ -n "${_NUTSHELL_TOML_JSON_SH:-}" ] && return 0
_NUTSHELL_TOML_JSON_SH=1

use super::toml

#[pub]
# Convert a TOML file to JSON, compact, keys in the order the file gives them.
#
# It writes the tree the reader built, so it is right on everything the reader
# reads: tables nest however the file reaches them, an array of tables is an
# array of objects, an inline table is an object, a dotted key is the nesting
# it spells, and every string is the decoded value escaped once for JSON.
# Integers come out in decimal and a date or a time as a string, as yq gives
# them.
#
# A file the reader refuses is refused here, rc 2 with its reason. So is an
# infinity or a NaN, which TOML has and JSON has no spelling for.
# Usage: toml_to_json "file.toml" -> prints JSON
toml_to_json() {
    local file="${1:-}" rc=0
    [[ -n "$file" ]] || return 1
    _toml_open_values "$file" || return $?
    _tj_out=""
    _tj_emit R || rc=$?
    if (( rc != 0 )); then
        printf 'toml: %s: %s\n' "$file" "$_tj_err" >&2
        return 2
    fi
    printf '%s\n' "$_tj_out"
}

# _tj_emit <node> -> the node appended to `_tj_out` as JSON
_tj_emit() {
    local node="$1" k i n first=1
    case "${_TOML_T[$node]}" in
        table)
            _tj_out+="$_TOML_LB"
            _toml_children "$node"
            local -a keys=("${_tc_keys[@]}")
            for k in "${keys[@]}"; do
                (( first )) || _tj_out+=","
                first=0
                _json_string_into _tj_s "$k"
                _tj_out+="${_tj_s}:"
                _tj_emit "$node$_TOML_US$k" || return 1
            done
            _tj_out+="$_TOML_RB" ;;
        array|aot)
            _tj_out+="["
            n="${_TOML_N[$node]}"
            for (( i = 0; i < n; i++ )); do
                (( i )) && _tj_out+=","
                _tj_emit "$node$_TOML_US$i" || return 1
            done
            _tj_out+="]" ;;
        str|dt)
            _json_string_into _tj_s "${_TOML_V[$node]}"
            _tj_out+="$_tj_s" ;;
        int|float|bool)
            _tj_out+="${_TOML_V[$node]}" ;;
        inf)
            _toml_node_show "$node"
            _tj_err="${_tn_out} is ${_TOML_V[$node]}, and JSON has no inf or nan"
            return 1 ;;
        *)
            _toml_node_show "$node"
            _tj_err="${_tn_out} has no type JSON can take"
            return 1 ;;
    esac
}

# _json_string_into <name> <text> -> the text as a JSON string, written to <name>
# Every control character is escaped, so the result is a JSON string whatever
# the TOML string held.
_json_string_into() {
    local __js_s="$2" __js_c __js_o="" __js_hex
    __js_s="${__js_s//\\/\\\\}"
    __js_s="${__js_s//\"/\\\"}"
    __js_s="${__js_s//$'\n'/\\n}"
    __js_s="${__js_s//$'\r'/\\r}"
    __js_s="${__js_s//$'\t'/\\t}"
    __js_s="${__js_s//$'\b'/\\b}"
    __js_s="${__js_s//$'\f'/\\f}"
    local LC_ALL=C
    while [[ "$__js_s" == *[$'\x01'-$'\x1f']* ]]; do
        __js_o+="${__js_s%%[$'\x01'-$'\x1f']*}"
        __js_s="${__js_s#"${__js_s%%[$'\x01'-$'\x1f']*}"}"
        __js_c="${__js_s:0:1}"
        printf -v __js_hex '\\u%04x' "'$__js_c"
        __js_o+="$__js_hex"
        __js_s="${__js_s:1}"
    done
    printf -v "$1" '"%s"' "$__js_o$__js_s"
}

# _json_string <text> -> prints the text as a JSON string
_json_string() {
    local s
    _json_string_into s "$1"
    printf '%s' "$s"
}
