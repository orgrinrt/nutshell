#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/impl/from_json.sh - the tree of what a tool prints as JSON
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Where taplo or mikefarah yq reads the file, what comes back is JSON. The json
# module's parser reads it, `lib/json/impl/bash_parse.sh`, standalone so the
# rest of json is not loaded with it, and this turns its tree into the one
# `lib/toml/impl/bash.sh` builds. There is one JSON parser and json owns it.

[ -n "${_NUTSHELL_TOML_IMPL_FROM_JSON_SH:-}" ] && return 0
_NUTSHELL_TOML_IMPL_FROM_JSON_SH=1

use super::toml::impl::bash_lex super::json::impl::bash_parse

# _toml_json_tree <id> <json> -> the tree of a tool's JSON, or rc 2 and `_TOML_ERR`
# The JSON is read by the json module's parser and its tree turned into the one
# the floor builds, so the accessors and the path language answer from either.
# JSON carries the values and not how the file spelled them: every object is a
# table flagged `j`, origin unknown; an array of tables is an array of tables
# written inline; a date is a string; and there is no `_TOML_R`, `_TOML_HDR` or
# line positions, which `_toml_full` goes to the floor for. A `null` or a key
# holding a separator has no tree here, and the caller then asks the floor.
#[pub(super)]
_toml_json_tree() {
    local LC_ALL=C
    _tp_id="$1" _tp_ln=0
    _TOML_T=() _TOML_V=() _TOML_R=() _TOML_K=() _TOML_N=() _TOML_F=()
    _TOML_HDR=() _TOML_ERR=""
    _TOML_W=() _TOML_P=() _TOML_C=() _TOML_E=()
    _jb_load "$2" || { _tp_err "json: the tool printed what is not JSON"; return 2; }
    [[ "${_JB_T[0]}" == object ]] || { _tp_err "json: the document is not a table"; return 2; }
    _toml_jt_node 0 R
}

# _toml_jt_node <json node> <toml node> -> the json node and all under it, as toml
_toml_jt_node() {
    local j="$1" t="$2" i n kid k
    n="${_JB_C[$j]-}"
    case "${_JB_T[$j]}" in
        object)
            _TOML_T[$t]=table _TOML_F[$t]=j _TOML_K[$t]=""
            for (( i = 0; i < n; i++ )); do
                kid="${_JB_CH[$j.$i]}" k="${_JB_KY[${_JB_CH[$j.$i]}]}"
                case "$k" in
                    *"$_TOML_US"*|*"$_TOML_RS"*)
                        _tp_err "json: a key holding a unit or record separator is not read"
                        return 2 ;;
                esac
                _TOML_K[$t]+="$_TOML_RS$k"
                _toml_jt_node "$kid" "$t$_TOML_US$k" || return 2
            done ;;
        array)
            _TOML_T[$t]=array _TOML_N[$t]=$n
            for (( i = 0; i < n; i++ )); do
                _toml_jt_node "${_JB_CH[$j.$i]}" "$t$_TOML_US$i" || return 2
            done ;;
        string)  _TOML_T[$t]=str _TOML_V[$t]="${_JB_V[$j]}" ;;
        boolean) _TOML_T[$t]=bool _TOML_V[$t]="${_JB_V[$j]}" ;;
        number)
            _TOML_T[$t]=float _TOML_V[$t]="${_JB_V[$j]}"
            [[ "${_JB_V[$j]}" == *[.eE]* ]] || _TOML_T[$t]=int ;;
        *)
            _tp_err "json: null has no TOML spelling"
            return 2 ;;
    esac
}
