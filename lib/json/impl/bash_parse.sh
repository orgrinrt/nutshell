#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/json/impl/bash_parse.sh - JSON parsed in bash alone
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The parser under `lib/json/impl/bash.sh`, the reader that runs wherever bash
# 4.3 does with no jq, no python and no perl, so a container with none of them
# still reads JSON. It only reads.
#
# The document is parsed once into a tree of numbered nodes and every question
# is answered from the tree. A node has a type in `_JB_T` and, for a scalar, its
# value in `_JB_V`, decoded. A container keeps its child count in `_JB_C` and
# its children as `_JB_CH[<node>.<index>]`; a child of an object remembers its
# key in `_JB_KY`. Nodes are numbers, not paths built from keys, so a key can
# hold any character at all.
#
# Strings are bytes, because the parse runs under `LC_ALL=C` where an offset is
# a byte count and reading is linear. The text a caller gets back is those
# bytes, which is UTF-8 when the document was. An escaped U+0000 cannot live in
# a bash string and is dropped.
#
# Output matches the other backends: a container comes back compact with its
# keys sorted bytewise, which for UTF-8 is code point order, a string bare, and
# any other scalar as the document wrote it. A repeated key keeps its last
# value, as jq does. Segments of a path arrive already split by the caller,
# joined by the unit separator, and the first path that does not lead anywhere
# is a miss with status 1.

[ -n "${_NUTSHELL_JSON_IMPL_BASH_PARSE_SH:-}" ] && return 0
_NUTSHELL_JSON_IMPL_BASH_PARSE_SH=1

declare -gA _JB_T=() _JB_V=() _JB_C=() _JB_CH=() _JB_KY=()
_JB_SRC="" _JB_SO=0 _JB_LEN=0 _JB_S="" _JB_SL=0 _JB_I=0
_JB_ID=0 _JB_DEPTH=0 _JB_TEXT="" _JB_RC=1 _JB_CHUNK=4096
_JB_US=$'\x1f'
_JB_RE_WS=$'^[ \t\n\r]*'
_JB_RE_PLAIN=$'^[^"\\\\\x01-\x1f]*'
_JB_RE_NUM='^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?'
_JB_RE_CTL=$'[\x01-\x07\x0b\x0e-\x1f\x7f]'

# The document is read through a buffer, `_JB_S`, with the cursor `_JB_I` in it
# and the rest still in `_JB_SRC` from `_JB_SO` on. Taking a character out of a
# long string costs the length of the string, so a parse over the whole text was
# quadratic and 94 KB took fourteen seconds. The buffer is a few KB, and what
# the cursor has passed is dropped each time it is refilled.

# _jb_more -> adds a chunk of the document to the buffer; rc 1 when none is left
_jb_more() {
    (( _JB_SO < _JB_LEN )) || return 1
    if (( _JB_I > 0 )); then _JB_S="${_JB_S:_JB_I}"; _JB_I=0; fi
    _JB_S+="${_JB_SRC:_JB_SO:_JB_CHUNK}"
    _JB_SO=$(( _JB_SO + _JB_CHUNK ))
    _JB_SL=${#_JB_S}
}

# _jb_need <n> -> at least n bytes ahead of the cursor, where the document has them
# Whatever it does not reach is for a regex, which asks for more itself.
_jb_need() {
    while (( _JB_SL - _JB_I < $1 )); do _jb_more || return 0; done
}

# _jb_re <regex> -> `_jb_m`, the match at the cursor
# A match that runs to the end of the buffer may go on in the document, so it is
# matched again with more of it.
_jb_re() {
    while :; do
        [[ "${_JB_S:_JB_I}" =~ $1 ]] || return 1
        _jb_m="${BASH_REMATCH[0]}"
        (( _JB_I + ${#_jb_m} < _JB_SL )) && return 0
        _jb_more || return 0
    done
}

# _jb_ws -> skips whitespace
_jb_ws() {
    case "${_JB_S:_JB_I:1}" in
        " "|$'\t'|$'\n'|$'\r') ;;
        ?) return 0 ;;
    esac
    _jb_re "$_JB_RE_WS"
    _JB_I=$(( _JB_I + ${#_jb_m} ))
}

# _jb_utf8 <code point> -> `_jb_u`, its UTF-8 bytes
_jb_utf8() {
    local c=$1
    if (( c < 0x80 )); then
        printf -v _jb_u '\\x%02x' "$c"
    elif (( c < 0x800 )); then
        printf -v _jb_u '\\x%02x\\x%02x' $(( 0xC0 | c >> 6 )) $(( 0x80 | c & 0x3F ))
    elif (( c < 0x10000 )); then
        printf -v _jb_u '\\x%02x\\x%02x\\x%02x' $(( 0xE0 | c >> 12 )) \
            $(( 0x80 | c >> 6 & 0x3F )) $(( 0x80 | c & 0x3F ))
    else
        printf -v _jb_u '\\x%02x\\x%02x\\x%02x\\x%02x' $(( 0xF0 | c >> 18 )) \
            $(( 0x80 | c >> 12 & 0x3F )) $(( 0x80 | c >> 6 & 0x3F )) $(( 0x80 | c & 0x3F ))
    fi
    printf -v _jb_u "$_jb_u"
}

# _jb_hex4 -> `_jb_cp`, the four hex digits at the cursor; rc 1 when they are not
_jb_hex4() {
    local h="${_JB_S:_JB_I:4}"
    [[ "$h" =~ ^[0-9A-Fa-f]{4}$ ]] || return 1
    _jb_cp=$(( 16#$h ))
    _JB_I=$(( _JB_I + 4 ))
}

# _jb_escape -> appends the escape after a backslash to `_jb_str`
_jb_escape() {
    _jb_need 16
    local c="${_JB_S:_JB_I:1}" hi
    _JB_I=$(( _JB_I + 1 ))
    case "$c" in
        '"') _jb_str+='"' ;;
        '\') _jb_str+='\' ;;
        '/') _jb_str+='/' ;;
        b) _jb_str+=$'\b' ;;
        f) _jb_str+=$'\f' ;;
        n) _jb_str+=$'\n' ;;
        r) _jb_str+=$'\r' ;;
        t) _jb_str+=$'\t' ;;
        u)
            _jb_hex4 || return 1
            if (( _jb_cp >= 0xD800 && _jb_cp < 0xDC00 )); then
                hi=$_jb_cp
                _jb_cp=0xFFFD
                if [[ "${_JB_S:_JB_I:2}" == '\u' ]]; then
                    _JB_I=$(( _JB_I + 2 ))
                    _jb_hex4 || return 1
                    if (( _jb_cp >= 0xDC00 && _jb_cp < 0xE000 )); then
                        _jb_cp=$(( 0x10000 + (hi - 0xD800) * 0x400 + _jb_cp - 0xDC00 ))
                    else
                        _JB_I=$(( _JB_I - 6 )); _jb_cp=0xFFFD
                    fi
                fi
            elif (( _jb_cp >= 0xDC00 && _jb_cp < 0xE000 )); then
                _jb_cp=0xFFFD
            fi
            (( _jb_cp )) || return 0
            _jb_utf8 "$_jb_cp"
            _jb_str+="$_jb_u" ;;
        *) return 1 ;;
    esac
}

# _jb_string -> `_jb_str`, the string at the cursor decoded; rc 1 when malformed
_jb_string() {
    _jb_str=""
    _JB_I=$(( _JB_I + 1 ))
    while :; do
        _jb_need 16
        _jb_re "$_JB_RE_PLAIN"
        _jb_str+="$_jb_m"
        _JB_I=$(( _JB_I + ${#_jb_m} ))
        case "${_JB_S:_JB_I:1}" in
            '"') _JB_I=$(( _JB_I + 1 )); return 0 ;;
            '\') _JB_I=$(( _JB_I + 1 )); _jb_escape || return 1 ;;
            *) return 1 ;;
        esac
    done
}

# _jb_attach <parent> <child> <key> -> adds a child; a repeated key is replaced
_jb_attach() {
    local p=$1 child=$2 key=$3 n i
    n="${_JB_C[$p]}"
    if [[ "${_JB_T[$p]}" == object ]]; then
        for (( i = 0; i < n; i++ )); do
            if [[ "${_JB_KY[${_JB_CH[$p.$i]}]}" == "$key" ]]; then
                _JB_CH[$p.$i]=$child; _JB_KY[$child]=$key
                return 0
            fi
        done
        _JB_KY[$child]=$key
    fi
    _JB_CH[$p.$n]=$child
    _JB_C[$p]=$(( n + 1 ))
}

# _jb_container <node> <close> -> parses the members of an object or array
_jb_container() {
    local id=$1 close=$2 key="" kid
    _JB_I=$(( _JB_I + 1 ))
    _jb_ws
    if [[ "${_JB_S:_JB_I:1}" == "$close" ]]; then _JB_I=$(( _JB_I + 1 )); return 0; fi
    while :; do
        _jb_ws
        if [[ "$close" == '}' ]]; then
            [[ "${_JB_S:_JB_I:1}" == '"' ]] || return 1
            _jb_string || return 1; key="$_jb_str"
            _jb_ws
            [[ "${_JB_S:_JB_I:1}" == ':' ]] || return 1
            _JB_I=$(( _JB_I + 1 )); _jb_ws
        fi
        _jb_value || return 1; kid=$_jb_id
        _jb_attach "$id" "$kid" "$key"
        _jb_ws
        case "${_JB_S:_JB_I:1}" in
            ,) _JB_I=$(( _JB_I + 1 )) ;;
            "$close") _JB_I=$(( _JB_I + 1 )); return 0 ;;
            *) return 1 ;;
        esac
    done
}

# _jb_value -> `_jb_id`, the node for the value at the cursor; rc 1 when malformed
_jb_value() {
    _jb_need 16
    local id=$_JB_ID c="${_JB_S:_JB_I:1}" rc=0
    _JB_ID=$(( _JB_ID + 1 ))
    (( _JB_DEPTH < 400 )) || return 1
    case "$c" in
        '{') _JB_T[$id]=object; _JB_C[$id]=0
             _JB_DEPTH=$(( _JB_DEPTH + 1 )); _jb_container "$id" '}' || rc=1
             _JB_DEPTH=$(( _JB_DEPTH - 1 )) ;;
        '[') _JB_T[$id]=array; _JB_C[$id]=0
             _JB_DEPTH=$(( _JB_DEPTH + 1 )); _jb_container "$id" ']' || rc=1
             _JB_DEPTH=$(( _JB_DEPTH - 1 )) ;;
        '"') _jb_string || return 1
             _JB_T[$id]=string; _JB_V[$id]="$_jb_str" ;;
        -|[0-9])
             _jb_re "$_JB_RE_NUM" || return 1
             _JB_T[$id]=number; _JB_V[$id]="$_jb_m"
             _JB_I=$(( _JB_I + ${#_jb_m} )) ;;
        *)   case "${_JB_S:_JB_I:5}" in
                 true*)  _JB_T[$id]=boolean; _JB_V[$id]=true;  _JB_I=$(( _JB_I + 4 )) ;;
                 false)  _JB_T[$id]=boolean; _JB_V[$id]=false; _JB_I=$(( _JB_I + 5 )) ;;
                 null*)  _JB_T[$id]=null;    _JB_V[$id]=null;  _JB_I=$(( _JB_I + 4 )) ;;
                 *) return 1 ;;
             esac ;;
    esac
    _jb_id=$id
    return $rc
}

# _jb_load <text> -> 0 parsed, 1 not JSON. The last document is kept.
#[pub(super)]
_jb_load() {
    local LC_ALL=C
    [[ "$_JB_TEXT" == "$1" && -n "$1" ]] && return "$_JB_RC"
    _JB_T=() _JB_V=() _JB_C=() _JB_CH=() _JB_KY=()
    _JB_SRC="$1" _JB_LEN=${#1} _JB_SO=0 _JB_S="" _JB_SL=0 _JB_I=0
    _JB_ID=0 _JB_DEPTH=0 _JB_RC=0
    _jb_ws
    if _jb_value; then
        _jb_ws
        (( _JB_I == _JB_SL && _JB_SO >= _JB_LEN )) || _JB_RC=1
    else
        _JB_RC=1
    fi
    _JB_TEXT="$1"
    return "$_JB_RC"
}

# _jb_find <path> -> `_jb_node`, the node a path names; rc 1 for none
#[pub(super)]
_jb_find() {
    local rest="${1:-}" seg node=0 n i found
    while [[ -n "$rest" ]]; do
        if [[ "$rest" == *"$_JB_US"* ]]; then seg="${rest%%"$_JB_US"*}"; rest="${rest#*"$_JB_US"}"
        else seg="$rest"; rest=""; fi
        [[ -n "$seg" ]] || continue
        n="${_JB_C[$node]-}"
        case "${_JB_T[$node]}" in
            array)
                [[ "$seg" =~ ^[0-9]{1,9}$ ]] || return 1
                (( 10#$seg < n )) || return 1
                node="${_JB_CH[$node.$(( 10#$seg ))]}" ;;
            object)
                found=""
                for (( i = n - 1; i >= 0; i-- )); do
                    if [[ "${_JB_KY[${_JB_CH[$node.$i]}]}" == "$seg" ]]; then found="${_JB_CH[$node.$i]}"; break; fi
                done
                [[ -n "$found" ]] || return 1
                node=$found ;;
            *) return 1 ;;
        esac
    done
    _jb_node=$node
}
