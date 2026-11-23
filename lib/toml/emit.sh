#!/usr/bin/env bash
# nutshell/toml/emit.sh - the floor's tree written as JSON
# https://github.com/orgrinrt/nutshell
#
# The one place that knows what JSON looks like, for `toml_to_json` and for the
# large-file path beside it. It walks the tree the reader built and writes it in
# one pass: compact, keys in the order the file gives them, every string the
# decoded value escaped once.
#
# The pieces go into an array and are joined once at the end. Appending to one
# growing string copies the whole of it each time in bash, so a 4 MB document
# written that way took longer than reading the TOML did.

[ -n "${_NUTSHELL_TOML_EMIT_SH:-}" ] && return 0
_NUTSHELL_TOML_EMIT_SH=1

use super::toml

declare -ga _tj_a=()

# A string that needs an escape: one holding a backslash, a double quote or a
# control character. Matched under `LC_ALL=C`, which the callers set, so the range is
# bytes.
_TJ_SPECIAL=$'*[\\\\"\x01-\x1f]*'

# Usage: _toml_emit_json -> `_tj_json`, the tree under the root as JSON
# rc 1 and `_tj_err` where the tree holds a value JSON has no spelling for.
#[pub(super)]
_toml_emit_json() {
    local LC_ALL=C IFS=
    _tj_a=() _tj_err="" _tj_json=""
    if ! _tj_node R; then
        _tj_a=()
        return 1
    fi
    _tj_json="${_tj_a[*]}"
    _tj_a=()
}

# _tj_node <node> -> the node and all under it appended to `_tj_a`
# A scalar under a table or an array is written where it is met, so the call to
# this function is paid per table and per array and not per value.
_tj_node() {
    local node="$1" k i n sep="" child t v
    case "${_TOML_T[$node]}" in
        table)
            _tj_a+=("$_TOML_LB")
            _toml_children "$node"
            local -a keys=("${_tc_keys[@]}")
            for k in "${keys[@]}"; do
                child="$node$_TOML_US$k"
                if [[ "$k" != $_TJ_SPECIAL ]]; then _tj_s="\"$k\""; else _json_string_into _tj_s "$k"; fi
                t="${_TOML_T[$child]}"
                case "$t" in
                    str|dt)
                        v="${_TOML_V[$child]}"
                        if [[ "$v" != $_TJ_SPECIAL ]]; then _tj_a+=("$sep$_tj_s:\"$v\"")
                        else _json_string_into _tj_v "$v"; _tj_a+=("$sep$_tj_s:$_tj_v"); fi ;;
                    int|float|bool)
                        _tj_a+=("$sep$_tj_s:${_TOML_V[$child]}") ;;
                    *)
                        _tj_a+=("$sep$_tj_s:")
                        _tj_node "$child" || return 1 ;;
                esac
                sep=","
            done
            _tj_a+=("$_TOML_RB") ;;
        array|aot)
            _tj_a+=("[")
            n="${_TOML_N[$node]}"
            for (( i = 0; i < n; i++ )); do
                child="$node$_TOML_US$i"
                case "${_TOML_T[$child]}" in
                    str|dt)
                        v="${_TOML_V[$child]}"
                        if [[ "$v" != $_TJ_SPECIAL ]]; then _tj_a+=("$sep\"$v\"")
                        else _json_string_into _tj_v "$v"; _tj_a+=("$sep$_tj_v"); fi ;;
                    int|float|bool)
                        _tj_a+=("$sep${_TOML_V[$child]}") ;;
                    *)
                        _tj_a+=("$sep")
                        _tj_node "$child" || return 1 ;;
                esac
                sep=","
            done
            _tj_a+=("]") ;;
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
    local __js_s="$2" __js_c __js_o="" __js_hex LC_ALL=C
    if [[ "$__js_s" != $_TJ_SPECIAL ]]; then
        printf -v "$1" '"%s"' "$__js_s"
        return 0
    fi
    __js_s="${__js_s//\\/\\\\}"
    __js_s="${__js_s//\"/\\\"}"
    __js_s="${__js_s//$'\n'/\\n}"
    __js_s="${__js_s//$'\r'/\\r}"
    __js_s="${__js_s//$'\t'/\\t}"
    __js_s="${__js_s//$'\b'/\\b}"
    __js_s="${__js_s//$'\f'/\\f}"
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
