#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/json/impl/bash.sh - JSON read in bash alone
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The floor under `lib/json.sh`: what is always there when jq, python and perl
# are not. It answers get, keys, type, length and valid, and nothing that
# writes. `lib/json.sh` refuses those with status 2 and says what would serve.
#
# What comes back is what the other backends print: a container compact with
# its keys sorted bytewise (code point order for UTF-8), a string bare, any
# other scalar as the document wrote it. A number is returned as written, so
# `1e3` stays `1e3` where jq spells it `1E+3`; that is the one place the
# backends can differ for a valid document.
#
# `lib/json/impl/bash_parse.sh` holds the parser and the path walk.

[ -n "${_NUTSHELL_JSON_IMPL_BASH_SH:-}" ] && return 0
_NUTSHELL_JSON_IMPL_BASH_SH=1

use super::json::impl::bash_parse

# _jb_esc <string> -> `_jb_e`, the string as a JSON literal wants it
_jb_esc() {
    local s="$1" ch hex
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\b'/\\b}"
    s="${s//$'\f'/\\f}"
    while [[ "$s" =~ $_JB_RE_CTL ]]; do
        ch="${BASH_REMATCH[0]}"
        printf -v hex '\\u%04x' "'$ch"
        s="${s/"$ch"/"$hex"}"
    done
    _jb_e="\"$s\""
}

# _jb_sort <node> -> `_jb_ord`, the children of an object ordered by key
_jb_sort() {
    local LC_ALL=C n="${_JB_C[$1]}" i j kid
    _jb_ord=()
    for (( i = 0; i < n; i++ )); do
        kid="${_JB_CH[$1.$i]}"
        for (( j = ${#_jb_ord[@]}; j > 0; j-- )); do
            [[ "${_JB_KY[${_jb_ord[j-1]}]}" > "${_JB_KY[$kid]}" ]] || break
            _jb_ord[j]="${_jb_ord[j-1]}"
        done
        _jb_ord[j]="$kid"
    done
}

# _jb_render <node> -> appends the node, compact and sorted, to `_jb_acc`
_jb_render() {
    local id=$1 n i kid first=1
    local -a ord
    case "${_JB_T[$id]}" in
        string)
            _jb_esc "${_JB_V[$id]}"; _jb_acc+="$_jb_e" ;;
        array)
            n="${_JB_C[$id]}"; _jb_acc+="["
            for (( i = 0; i < n; i++ )); do
                (( first )) || _jb_acc+=","
                first=0
                _jb_render "${_JB_CH[$id.$i]}"
            done
            _jb_acc+="]" ;;
        object)
            _jb_sort "$id"; ord=("${_jb_ord[@]}"); _jb_acc+="{"
            for kid in "${ord[@]}"; do
                (( first )) || _jb_acc+=","
                first=0
                _jb_esc "${_JB_KY[$kid]}"; _jb_acc+="$_jb_e:"
                _jb_render "$kid"
            done
            _jb_acc+="}" ;;
        *)
            _jb_acc+="${_JB_V[$id]}" ;;
    esac
}

# _jb_at <json> <path> -> `_jb_node`; rc 1 when it is not JSON or the path is not there
_jb_at() {
    _jb_load "$1" || return 1
    _jb_find "${2:-}"
}

_json_get_bash() {
    local LC_ALL=C
    _jb_at "$1" "${2:-}" || return 1
    case "${_JB_T[$_jb_node]}" in
        array|object) _jb_acc=""; _jb_render "$_jb_node"; printf '%s\n' "$_jb_acc" ;;
        *) printf '%s\n' "${_JB_V[$_jb_node]}" ;;
    esac
}

_json_valid_bash() {
    _jb_load "$1"
}

_json_type_bash() {
    _jb_at "$1" "${2:-}" || return 1
    printf '%s\n' "${_JB_T[$_jb_node]}"
}

_json_keys_bash() {
    local LC_ALL=C kid i
    _jb_at "$1" "${2:-}" || return 1
    case "${_JB_T[$_jb_node]}" in
        array)  for (( i = 0; i < _JB_C[$_jb_node]; i++ )); do printf '%s\n' "$i"; done ;;
        object) _jb_sort "$_jb_node"
                for kid in "${_jb_ord[@]}"; do printf '%s\n' "${_JB_KY[$kid]}"; done ;;
        *)      return 1 ;;
    esac
}

# A string's length is in characters, so this one runs in the caller's locale.
_json_length_bash() {
    _jb_at "$1" "${2:-}" || return 1
    case "${_JB_T[$_jb_node]}" in
        array|object) printf '%s\n' "${_JB_C[$_jb_node]}" ;;
        string)       printf '%s\n' "${#_JB_V[$_jb_node]}" ;;
        null)         printf '0\n' ;;
        *)            return 1 ;;
    esac
}
