#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/impl/bash.sh - the TOML reader in bash alone
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The floor under `lib/toml.sh`: the reader that runs wherever bash 4.3 does,
# with no external tool and no other nutshell module. A faster backend may sit
# above it later; this one is what is always there.
#
# It reads a file into a tree once and answers every question from the tree.
# The grammar is TOML 1.0 in full, or the file is refused: rc 2, and the
# construct and line named in `_TOML_ERR`. A construct it does not read is an
# error, never a key that quietly is not there.
#
# The tree is six associative arrays keyed by node path, as
# `lib/toml/impl/bash_path.sh` spells one.
#
#   _TOML_T  type: table, aot, array, str, int, float, bool, dt, inf
#   _TOML_V  the value of a scalar, decoded
#   _TOML_R  every value as written in the file
#   _TOML_K  the keys of a table in file order, each led by the record separator
#   _TOML_N  the length of an array or array of tables
#   _TOML_F  how a table came to be: h header, i implicit, d dotted, X inline;
#            on a scalar read from a tool's JSON, L where the tool rewrites its type
#
# `_TOML_HDR` lists the tables named by a header, in the order first seen.
#
# Where each thing sits in the file, for the writer, which edits by line and
# finds the line here rather than with a scanner of its own. Line numbers
# count from 0.
#
#   _TOML_W  for a key set by `key = value` outside an inline table: its first
#            line, its last, and how many segments the key was written with
#   _TOML_P  the same key's first line up to its value, indent and key and `=`
#   _TOML_C  what follows the value on its last line, the comment with its gap
#   _TOML_E  for the root and each table a header opens, the last line of its
#            part of the file that holds a header or a key, -1 for none

# A guard of its own rather than `nut_once`, for the same reason as every file
# that can be sourced before the module system exists.
[ -n "${_NUTSHELL_TOML_IMPL_BASH_SH:-}" ] && return 0
_NUTSHELL_TOML_IMPL_BASH_SH=1

# Declared as modules where the module system runs, sourced by path where it
# does not, so `deps` and `extern` can stand on this file before anything else
# is loaded.
if declare -F use >/dev/null 2>&1; then
    use super::toml::impl::bash_lex super::toml::impl::bash_path
else
    source "${BASH_SOURCE[0]%/*}/bash_lex.sh"
    source "${BASH_SOURCE[0]%/*}/bash_path.sh"
fi

# The two brace characters, spelled so that no function body carries a lone one.
_TOML_LB=$'\x7b'
_TOML_RB=$'\x7d'
_TOML_RE_BLANK='^[[:blank:]]*(#.*)?$'
_TOML_RE_BARE='^[A-Za-z0-9_-]+'

declare -gA _TOML_T=() _TOML_V=() _TOML_R=() _TOML_K=() _TOML_N=() _TOML_F=()
declare -gA _TOML_W=() _TOML_P=() _TOML_C=() _TOML_E=()
declare -ga _TOML_HDR=() _tp_kseg=()
_TOML_ID=""
_TOML_SRC=""
_TOML_RC=0

# _toml_load <file> -> 0 read, 1 no such file, 2 not TOML (`_TOML_ERR` says why)
# The tree of the last file read is kept, and reused while the file is unchanged.
#[pub(super)]
_toml_load() {
    local f="$1" c=""
    [[ -f "$f" && -r "$f" ]] || return 1
    if IFS= read -r -d '' c < "$f"; then
        _TOML_ID="" _TOML_ERR="toml: ${f}: the file holds a NUL byte"
        return 2
    fi
    if [[ "$_TOML_ID" == "$f" && "$_TOML_SRC" == "$c" ]]; then
        return "$_TOML_RC"
    fi
    _TOML_RC=0
    _toml_parse_text "$f" "$c" || _TOML_RC=$?
    _TOML_ID="$f" _TOML_SRC="$c"
    return "$_TOML_RC"
}

# _toml_parse_text <id> <text> -> the tree, or rc 2 and `_TOML_ERR`
#[pub(lib)]
_toml_parse_text() {
    local LC_ALL=C
    _tp_id="$1"
    _TOML_T=() _TOML_V=() _TOML_R=() _TOML_K=() _TOML_N=() _TOML_F=()
    _TOML_HDR=() _TOML_ERR=""
    _TOML_W=() _TOML_P=() _TOML_C=() _TOML_E=()
    _TOML_T[R]=table
    _TOML_K[R]=""
    _TOML_E[R]=-1
    mapfile -t _TL <<< "$2"
    _TL[0]="${_TL[0]#$'\xef\xbb\xbf'}"
    _TL=("${_TL[@]%$'\r'}")
    _tp_ln=0
    _tp_cur=R
    local n=${#_TL[@]}
    while (( _tp_ln < n )); do
        _tp_s="${_TL[_tp_ln]}"
        if ! [[ "$_tp_s" =~ $_TOML_RE_BLANK ]]; then
            _tp_skip_ws
            if [[ "$_tp_s" == '['* ]]; then
                _tp_header || return 2
            else
                _tp_keyval "$_tp_cur" "" || return 2
            fi
            _tp_eol || return 2
        fi
        _tp_ln=$(( _tp_ln + 1 ))
    done
    return 0
}

# _tp_key -> `_tp_kseg` holds the segments of a bare, quoted or dotted key
_tp_key() {
    _tp_kseg=()
    local seg
    while :; do
        _tp_skip_ws
        if [[ "$_tp_s" =~ $_TOML_RE_BARE ]]; then
            seg="${BASH_REMATCH[0]}"
            _tp_s="${_tp_s:${#seg}}"
        elif [[ "$_tp_s" == '"'* ]]; then
            _tp_s="${_tp_s:1}"
            [[ "$_tp_s" =~ $_TOML_RE_BSTR ]] || { _tp_err "unterminated quoted key"; return 2; }
            _tp_s="${_tp_s:${#BASH_REMATCH[0]}}"
            _tv_unescape "${BASH_REMATCH[1]}" || return 2
            seg="$_tv_out"
        elif [[ "$_tp_s" == "'"* ]]; then
            [[ "$_tp_s" =~ $_TOML_RE_LSTR ]] || { _tp_err "unterminated quoted key"; return 2; }
            _tp_s="${_tp_s:${#BASH_REMATCH[0]}}"
            seg="${BASH_REMATCH[1]}"
        else
            _tp_err "expected a key at: ${_tp_s}"
            return 2
        fi
        case "$seg" in
            *"$_TOML_US"*|*"$_TOML_RS"*)
                _tp_err "a key holding a unit or record separator is not read"
                return 2 ;;
        esac
        _tp_kseg+=("$seg")
        _tp_skip_ws
        [[ "$_tp_s" == .* ]] || return 0
        _tp_s="${_tp_s:1}"
    done
}

# _tp_err_key <format> -> the error of that format, the key being parsed spelled
# in place of its one `%s`
#
# Spelling the key for every key, against the chance of a message, was a tenth
# of the parse, and nearly every key parses without one. The segments are still
# `_tp_kseg` wherever this is called from: every one of those sites is reached
# before the value under the key is read.
_tp_err_key() {
    local i kn=""
    for (( i = 0; i < ${#_tp_kseg[@]}; i++ )); do
        _toml_seg_show "${_tp_kseg[i]}"
        kn+="${kn:+.}${_ts_out}"
    done
    _tp_err "${1//%s/$kn}"
}

# _tp_new <parent> <key> <type> <flags> -> `_tp_node`, a new child of a table
_tp_new() {
    _tp_node="$1$_TOML_US$2"
    _TOML_T[$_tp_node]="$3"
    _TOML_F[$_tp_node]="$4"
    [[ "$3" == table ]] && _TOML_K[$_tp_node]=""
    _TOML_K[$1]+="$_TOML_RS$2"
}

# `[a.b]` and `[[a.b]]`.
_tp_header() {
    local aot=0
    if [[ "$_tp_s" == '[['* ]]; then
        aot=1
        _tp_s="${_tp_s:2}"
    else
        _tp_s="${_tp_s:1}"
    fi
    _tp_key || return 2
    _tp_skip_ws
    if (( aot )); then
        [[ "$_tp_s" == ']]'* ]] || { _tp_err "array of tables header not closed by ]]"; return 2; }
        _tp_s="${_tp_s:2}"
    else
        [[ "$_tp_s" == ']'* ]] || { _tp_err "table header not closed by ]"; return 2; }
        _tp_s="${_tp_s:1}"
    fi
    local node=R i last=$(( ${#_tp_kseg[@]} - 1 )) child t f n
    for (( i = 0; i < last; i++ )); do
        child="$node$_TOML_US${_tp_kseg[i]}"
        t="${_TOML_T[$child]-}"
        f="${_TOML_F[$child]-}"
        case "$t" in
            '')
                _tp_new "$node" "${_tp_kseg[i]}" table i ;;
            aot)
                n="${_TOML_N[$child]}"
                child="$child$_TOML_US$(( n - 1 ))" ;;
            table)
                [[ "$f" == *X* ]] && { _tp_err_key "header %s extends an inline table"; return 2; } ;;
            *)
                _tp_err_key "header %s runs into a value, a key defined twice"
                return 2 ;;
        esac
        node="$child"
    done
    child="$node$_TOML_US${_tp_kseg[last]}"
    t="${_TOML_T[$child]-}"
    f="${_TOML_F[$child]-}"
    if (( aot )); then
        if [[ -z "$t" ]]; then
            _tp_new "$node" "${_tp_kseg[last]}" aot h
            _TOML_N[$child]=0
            _TOML_HDR+=("$child")
        elif [[ "$t" != aot ]]; then
            _tp_err_key "array of tables %s names a key defined twice"
            return 2
        fi
        n="${_TOML_N[$child]}"
        _TOML_T[$child$_TOML_US$n]=table
        _TOML_F[$child$_TOML_US$n]=h
        _TOML_K[$child$_TOML_US$n]=""
        _TOML_N[$child]=$(( n + 1 ))
        _tp_cur="$child$_TOML_US$n"
        _TOML_E[$_tp_cur]=$_tp_ln
        return 0
    fi
    case "$t" in
        '')
            _tp_new "$node" "${_tp_kseg[last]}" table h
            _TOML_HDR+=("$child") ;;
        table)
            if [[ "$f" == *X* ]]; then
                _tp_err_key "table %s is an inline table already"; return 2
            elif [[ "$f" == *h* ]]; then
                _tp_err_key "table %s defined twice"; return 2
            elif [[ "$f" == *d* ]]; then
                _tp_err_key "table %s was made by dotted keys and cannot take a header"; return 2
            fi
            _TOML_F[$child]="${f}h"
            _TOML_HDR+=("$child") ;;
        *)
            _tp_err_key "table %s names a key defined twice"
            return 2 ;;
    esac
    _tp_cur="$child"
    _TOML_E[$child]=$_tp_ln
}

# _tp_keyval <table> <X inside an inline table, else empty> -> one `key = value`
_tp_keyval() {
    local tbl="$1" inl="$2" node i last child t f from=$_tp_ln pre
    _tp_key || return 2
    _tp_skip_ws
    [[ "$_tp_s" == '='* ]] || { _tp_err "expected = after the key"; return 2; }
    _tp_s="${_tp_s:1}"
    _tp_skip_ws
    pre="${_TL[from]:0:${#_TL[from]}-${#_tp_s}}"
    node="$tbl"
    last=$(( ${#_tp_kseg[@]} - 1 ))
    for (( i = 0; i < last; i++ )); do
        child="$node$_TOML_US${_tp_kseg[i]}"
        t="${_TOML_T[$child]-}"
        f="${_TOML_F[$child]-}"
        case "$t" in
            '')
                _tp_new "$node" "${_tp_kseg[i]}" table "d$inl" ;;
            table)
                if [[ "$f" == *d* ]] && [[ -n "$inl" || "$f" != *X* ]]; then
                    :
                elif [[ "$f" == *X* ]]; then
                    _tp_err_key "dotted key %s extends an inline table"; return 2
                else
                    _tp_err_key "dotted key %s reopens a table defined by a header"; return 2
                fi ;;
            aot)
                _tp_err_key "dotted key %s runs into an array of tables"; return 2 ;;
            *)
                _tp_err_key "dotted key %s runs into a value, a key defined twice"; return 2 ;;
        esac
        node="$child"
    done
    child="$node$_TOML_US${_tp_kseg[last]}"
    [[ -z "${_TOML_T[$child]-}" ]] || { _tp_err_key "key %s defined twice"; return 2; }
    _TOML_K[$node]+="$_TOML_RS${_tp_kseg[last]}"
    _tv_value "$child" || return 2
    [[ -z "$inl" ]] || return 0
    _TOML_W[$child]="$from $_tp_ln $(( last + 1 ))"
    _TOML_P[$child]="$pre"
    _TOML_C[$child]="$_tp_s"
    _TOML_E[$tbl]=$_tp_ln
}

# _tv_value <node> -> the value at the cursor, typed and stored under <node>
_tv_value() {
    local p="$1" m_s="$_tp_s" m_ln=$_tp_ln
    case "${_tp_s:0:1}" in
        '"')
            if [[ "$_tp_s" == '"""'* ]]; then _tv_mlstr "$p" '"'; else _tv_basic "$p"; fi ;;
        "'")
            if [[ "$_tp_s" == "'''"* ]]; then _tv_mlstr "$p" "'"; else _tv_literal "$p"; fi ;;
        '[')
            _tv_array "$p" ;;
        "$_TOML_LB")
            _tv_inline "$p" ;;
        '')
            _tp_err "expected a value"; return 2 ;;
        *)
            _tv_scalar "$p" ;;
    esac || return 2
    _tv_raw "$p" "$m_s" "$m_ln"
}

# _tv_array <node> -> `[ ... ]`, its elements stored under <node>.0, <node>.1, ...
_tv_array() {
    local p="$1" idx=0
    _TOML_T[$p]=array
    _tp_s="${_tp_s:1}"
    while :; do
        _tp_skip_wsnl || return 2
        if [[ "$_tp_s" == ']'* ]]; then
            _tp_s="${_tp_s:1}"
            break
        fi
        _tv_value "$p$_TOML_US$idx" || return 2
        idx=$(( idx + 1 ))
        _tp_skip_wsnl || return 2
        case "${_tp_s:0:1}" in
            ,)
                _tp_s="${_tp_s:1}" ;;
            ']')
                _tp_s="${_tp_s:1}"
                break ;;
            *)
                _tp_err "array: expected , or ] at: ${_tp_s}"
                return 2 ;;
        esac
    done
    _TOML_N[$p]=$idx
}

# _tv_inline <node> -> an inline table, on one line as TOML 1.0 requires
_tv_inline() {
    local p="$1"
    _TOML_T[$p]=table
    _TOML_F[$p]=X
    _TOML_K[$p]=""
    _tp_s="${_tp_s:1}"
    _tp_skip_ws
    if [[ "$_tp_s" == "$_TOML_RB"* ]]; then
        _tp_s="${_tp_s:1}"
        return 0
    fi
    while :; do
        _tp_skip_ws
        [[ -n "$_tp_s" ]] || { _tp_err "inline table spans lines"; return 2; }
        _tp_keyval "$p" X || return 2
        _tp_skip_ws
        case "${_tp_s:0:1}" in
            ,)
                _tp_s="${_tp_s:1}" ;;
            "$_TOML_RB")
                _tp_s="${_tp_s:1}"
                return 0 ;;
            '')
                _tp_err "inline table spans lines"
                return 2 ;;
            *)
                _tp_err "inline table: expected a comma or its closing brace at: ${_tp_s}"
                return 2 ;;
        esac
    done
}
