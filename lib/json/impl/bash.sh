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
# `1e3` stays `1e3`; the other backends hand a number, and a container with
# one spelled in a way their own printer would change, to this reader.
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

#[pub(super)]
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

# A string's length is in characters whatever the locale: under `C` every byte
# but a UTF-8 continuation byte, 0x80 to 0xBF, starts one.
_json_length_bash() {
    local LC_ALL=C s
    _jb_at "$1" "${2:-}" || return 1
    case "${_JB_T[$_jb_node]}" in
        array|object) printf '%s\n' "${_JB_C[$_jb_node]}" ;;
        string)       s="${_JB_V[$_jb_node]}"
                      s="${s//[$'\x80'-$'\xbf']/}"
                      printf '%s\n' "${#s}" ;;
        null)         printf '0\n' ;;
        *)            return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Answering on jq's behalf
# -----------------------------------------------------------------------------
#
# `lib/json.sh` asks the floor first for a plain path of a small document, with
# jq or another tool behind it, so a hook reading one field of its payload
# runs no tool at all. The floor answers only where its text is the tool's to
# the byte; anything else it hands back. The document has to parse; a string
# in it has to be one jq prints as written (valid UTF-8, no NUL, no lone
# surrogate); and the path has to mean to the floor what it means to jq. A
# number is never handed back: every backend prints it as the document wrote
# it, so the floor's answer is the one they give.

# _jb_utf8_ok <text> -> rc 0 where the text is UTF-8 throughout. Each well
# formed sequence is replaced by one ASCII byte, so two fragments of a bad one
# never meet, and any byte above 0x7f left over is bad. The last answer is
# kept with its text.
_JB_U8_TEXT="" _JB_U8_RC=0
_jb_utf8_ok() {
    local LC_ALL=C s="$1" c=$'[\x80-\xbf]'
    [[ "$s" == "$_JB_U8_TEXT" ]] && return "$_JB_U8_RC"
    s="${s//$'\xf0'[$'\x90'-$'\xbf']$c$c/.}"
    s="${s//[$'\xf1'-$'\xf3']$c$c$c/.}"
    s="${s//$'\xf4'[$'\x80'-$'\x8f']$c$c/.}"
    s="${s//$'\xe0'[$'\xa0'-$'\xbf']$c/.}"
    s="${s//[$'\xe1'-$'\xec'$'\xee'$'\xef']$c$c/.}"
    s="${s//$'\xed'[$'\x80'-$'\x9f']$c/.}"
    s="${s//[$'\xc2'-$'\xdf']$c/.}"
    _JB_U8_TEXT="$1" _JB_U8_RC=0
    [[ "$s" == *[$'\x80'-$'\xff']* ]] && _JB_U8_RC=1
    return "$_JB_U8_RC"
}

# _json_floor <get|has|type|keys|length> <json> <segments> -> what the tool
# would print; rc 0 answered, 1 not there, 3 the tool's to answer
# Usage: _json_floor get "$json" "$segments" -> the value, as jq prints it
#[pub(super)]
_json_floor() {
    local LC_ALL=C op="$1" t s _JB_JQ_PATH=1 rc=0 _JB_MAXN="${_JSON_FLOOR_NODES:-64}"
    _jb_load "$2" || return 3
    (( _JB_ODDH )) && return 3
    (( _JB_ODDS )) && [[ "$op" != type ]] && return 3
    if [[ "$2" == *[$'\x80'-$'\xff']* ]]; then _jb_utf8_ok "$2" || return 3; fi
    _jb_find "${3:-}" || rc=$?
    case "$rc" in 0) ;; 1) return 1 ;; *) return 3 ;; esac
    t="${_JB_T[$_jb_node]}"
    case "$op:$t" in
        get:array|get:object)
            _jb_acc=""; _jb_render "$_jb_node"; printf '%s\n' "$_jb_acc" ;;
        get:*)        printf '%s\n' "${_JB_V[$_jb_node]}" ;;
        # What `json_has` meant through a capture of `json_get`: present, and
        # printing neither nothing nor `null` once trailing newlines are cut.
        has:null)     return 1 ;;
        has:string)
            s="${_JB_V[$_jb_node]}"
            while [[ "$s" == *$'\n' ]]; do s="${s%$'\n'}"; done
            [[ -n "$s" && "$s" != null ]] || return 1 ;;
        has:*)        return 0 ;;
        type:*)       printf '%s\n' "$t" ;;
        keys:array|keys:object) _json_keys_bash "$2" "${3:-}" ;;
        length:array|length:object|length:string|length:null) _json_length_bash "$2" "${3:-}" ;;
        *)            return 3 ;;
    esac
}
