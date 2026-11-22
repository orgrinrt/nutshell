#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/impl/json_tree.sh - the tree read from a tool's JSON
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Where mikefarah yq or taplo reads the file, what comes back is JSON, and this
# turns it into the same tree `lib/toml/impl/bash.sh` builds, so the accessors
# and the path language in `lib/toml/impl/bash_path.sh` answer from either.
#
# JSON carries the values and not how the file spelled them, so the tree from
# it has less in it: every object is a table flagged `j`, origin unknown, where
# the floor knows a header from a dotted key from an inline table; an array of
# tables is an array of tables written inline; a date is a string; and there is
# no `_TOML_R`, `_TOML_HDR` or line positions. `lib/toml.sh` asks the floor
# for whatever turns on those.
#
# The JSON is read line by line, a token at a time with a state for what may
# come next, so a tool's pretty output costs one short line per value. Anything
# that is not JSON a TOML file could have produced, a `null` or a key holding a
# separator, is rc 2 with `_TOML_ERR`, and the caller then asks the floor.

[ -n "${_NUTSHELL_TOML_IMPL_JSON_TREE_SH:-}" ] && return 0
_NUTSHELL_TOML_IMPL_JSON_TREE_SH=1

use super::toml::impl::bash super::toml::impl::bash_lex

_TOML_RE_JLIT='^(true|false|null|-?[0-9][0-9.eE+-]*)'
_TOML_RE_JINT='^-?[0-9]+$'
declare -ga _tj_stack=()

# _toml_json_tree <id> <json> -> the tree, or rc 2 and `_TOML_ERR`
#[pub(super)]
_toml_json_tree() {
    local LC_ALL=C n
    _tp_id="$1"
    _TOML_T=() _TOML_V=() _TOML_R=() _TOML_K=() _TOML_N=() _TOML_F=()
    _TOML_HDR=() _TOML_ERR=""
    _TOML_W=() _TOML_P=() _TOML_C=() _TOML_E=()
    _tj_stack=() _tj_key="" _tj_st=v
    mapfile -t _TL <<< "$2"
    n=${#_TL[@]}
    for (( _tp_ln = 0; _tp_ln < n; _tp_ln++ )); do
        _tp_s="${_TL[_tp_ln]}"
        while :; do
            _tp_s="${_tp_s#"${_tp_s%%[![:space:]]*}"}"
            [[ -n "$_tp_s" ]] || break
            _tj_token || return 2
        done
    done
    [[ "$_tj_st" == e ]] || { _tp_err "json: the text ends inside a value"; return 2; }
}

# _tj_token -> one token off the front of `_tp_s`, applied to the tree
# States: v a value, V a value or `]`, K a key or `}`, k a key, : the colon,
# c a comma or the closer of the open container, e the end.
_tj_token() {
    local c="${_tp_s:0:1}" top="" d=${#_tj_stack[@]}
    (( d )) && top="${_tj_stack[d-1]}"
    case "$_tj_st$c" in
        [vV]'{'|[vV]'[')
            _tj_place || return 2
            _tp_s="${_tp_s:1}"
            if [[ "$c" == '{' ]]; then
                _TOML_T[$_tj_node]=table _TOML_F[$_tj_node]=j _TOML_K[$_tj_node]="" _tj_st=K
            else
                _TOML_T[$_tj_node]=array _TOML_N[$_tj_node]=0 _tj_st=V
            fi
            _tj_stack+=("$_tj_node") ;;
        [Kc]'}'|[Vc]']')
            [[ -n "$top" ]] || { _tp_err "json: a closer with nothing open"; return 2; }
            [[ "$c" == '}' && "${_TOML_T[$top]}" == table || "$c" == ']' && "${_TOML_T[$top]}" == array ]] \
                || { _tp_err "json: ${c} closes the wrong container"; return 2; }
            _tp_s="${_tp_s:1}"
            unset "_tj_stack[d-1]"
            _tj_st=c
            (( ${#_tj_stack[@]} )) || _tj_st=e ;;
        c,)
            _tp_s="${_tp_s:1}"
            _tj_st=v
            [[ "${_TOML_T[$top]}" != table ]] || _tj_st=k ;;
        :':')
            _tp_s="${_tp_s:1}"
            _tj_st=v ;;
        [kK]'"')
            _tj_string || return 2
            case "$_tv_out" in
                *"$_TOML_US"*|*"$_TOML_RS"*)
                    _tp_err "json: a key holding a unit or record separator is not read"
                    return 2 ;;
            esac
            _tj_key="$_tv_out" _tj_st=:
            # The colon is all that may follow, so it is taken here.
            if [[ "$_tp_s" =~ ^[[:space:]]*:[[:space:]]* ]]; then
                _tp_s="${_tp_s:${#BASH_REMATCH[0]}}" _tj_st=v
            fi ;;
        [vV]'"')
            _tj_place || return 2
            _tj_string || return 2
            _TOML_T[$_tj_node]=str _TOML_V[$_tj_node]="$_tv_out" _tj_st=c ;;
        [vV]?)
            [[ "$_tp_s" =~ $_TOML_RE_JLIT ]] || { _tp_err "json: unexpected text: ${_tp_s}"; return 2; }
            c="${BASH_REMATCH[1]}"
            _tp_s="${_tp_s:${#c}}"
            [[ "$c" != null ]] || { _tp_err "json: null has no TOML spelling"; return 2; }
            _tj_place || return 2
            case "$c" in
                true|false) _TOML_T[$_tj_node]=bool ;;
                *) [[ "$c" =~ $_TOML_RE_JINT ]] && _TOML_T[$_tj_node]=int || _TOML_T[$_tj_node]=float ;;
            esac
            _TOML_V[$_tj_node]="$c" _tj_st=c ;;
        *)
            _tp_err "json: unexpected text: ${_tp_s}"
            return 2 ;;
    esac
}

# _tj_place -> `_tj_node`, where the next value goes: the root, the next key of
# the open table or the next element of the open array
_tj_place() {
    local top="" d=${#_tj_stack[@]}
    (( d )) && top="${_tj_stack[d-1]}"
    if [[ -z "$top" ]]; then
        [[ "$_tp_s" == '{'* ]] || { _tp_err "json: the document is not a table"; return 2; }
        _tj_node=R
    elif [[ "${_TOML_T[$top]}" == table ]]; then
        _tj_node="$top$_TOML_US$_tj_key"
        [[ -z "${_TOML_T[$_tj_node]-}" ]] || { _tp_err "json: a key given twice"; return 2; }
        _TOML_K[$top]+="$_TOML_RS$_tj_key"
    else
        _tj_node="$top$_TOML_US${_TOML_N[$top]}"
        local i="${_TOML_N[$top]}"
        _TOML_N[$top]=$(( i + 1 ))
    fi
}

# _tj_string -> `_tv_out`, the JSON string at the front of `_tp_s`, decoded
# The escapes JSON has and TOML has not, `\/` and a surrogate pair, are refused
# by the TOML decoder, which sends the file to the floor; neither tool writes
# them.
_tj_string() {
    _tp_s="${_tp_s:1}"
    [[ "$_tp_s" =~ $_TOML_RE_BSTR ]] || { _tp_err "json: unterminated string"; return 2; }
    _tp_s="${_tp_s:${#BASH_REMATCH[0]}}"
    _tv_unescape "${BASH_REMATCH[1]}"
}
