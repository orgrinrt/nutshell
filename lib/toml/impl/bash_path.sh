#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/impl/bash_path.sh - the path language over the tree
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# One path language for toml and json: `a.b.0.c`, where a dot separates
# segments, a numeric segment indexes an array or an array of tables, and a
# segment in double quotes is one segment whatever it holds, with `\` escaping
# the next character inside it. An unquoted segment is trimmed.
#
# A path names a node of the tree `lib/toml/impl/bash.sh` builds. A node is
# `R` for the root, and each step below it adds the unit separator and a key,
# or an index for an element of an array.

[ -n "${_NUTSHELL_TOML_IMPL_BASH_PATH_SH:-}" ] && return 0
_NUTSHELL_TOML_IMPL_BASH_PATH_SH=1

_TOML_US=$'\x1f'
_TOML_RS=$'\x1e'

declare -gA _TOML_T=() _TOML_N=()
declare -ga _tp_pseg=()

# _toml_valid_target <name> -> whether a caller's variable name is safe to write
# `printf -v` evaluates an array subscript, so only a plain name is taken, and
# the reserved prefix is refused outright instead of hoped about.
_toml_valid_target() {
    case "$1" in
        __toml_*) return 1 ;;
    esac
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

# _toml_trim_into <name> <text> -> the text trimmed, written to <name>
#[pub(super)]
_toml_trim_into() {
    _toml_valid_target "$1" || return 2
    local __toml_v="$2"
    __toml_v="${__toml_v#"${__toml_v%%[![:space:]]*}"}"
    __toml_v="${__toml_v%"${__toml_v##*[![:space:]]}"}"
    printf -v "$1" '%s' "$__toml_v"
}

# _toml_seg_show <segment> -> `_ts_out`, the segment as a path would spell it
#[pub(lib)]
_toml_seg_show() {
    if [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; then
        _ts_out="$1"
    else
        local s="${1//\\/\\\\}"
        _ts_out="\"${s//\"/\\\"}\""
    fi
}

# _toml_path_split <path> -> `_tp_pseg`; rc 2 when a quote never closes
#[pub(lib)]
_toml_path_split() {
    local s="$1" seg="" c i n=${#1} q=0 quoted=0
    _tp_pseg=()
    for (( i = 0; i < n; i++ )); do
        c="${s:i:1}"
        if (( q )); then
            if [[ "$c" == '\' ]]; then
                i=$(( i + 1 ))
                seg+="${s:i:1}"
            elif [[ "$c" == '"' ]]; then
                q=0
            else
                seg+="$c"
            fi
            continue
        fi
        case "$c" in
            '"')
                q=1 quoted=1 seg="" ;;
            .)
                _toml_path_push
                seg="" quoted=0 ;;
            ' '|$'\t')
                (( quoted )) || seg+="$c" ;;
            *)
                seg+="$c" ;;
        esac
    done
    (( q )) && return 2
    _toml_path_push
    return 0
}

_toml_path_push() {
    (( quoted )) || _toml_trim_into seg "$seg"
    _tp_pseg+=("$seg")
}

# _toml_lookup -> `_tl_node`, the node `_tp_pseg` names; rc 1 when there is none
#[pub(super)]
_toml_lookup() {
    local node=R seg t n
    for seg in "${_tp_pseg[@]}"; do
        t="${_TOML_T[$node]-}"
        case "$t" in
            table)
                node="$node$_TOML_US$seg"
                [[ -n "${_TOML_T[$node]-}" ]] || return 1 ;;
            array|aot)
                [[ "$seg" =~ ^[0-9]{1,9}$ ]] || return 1
                n="${_TOML_N[$node]}"
                (( 10#$seg < n )) || return 1
                node="$node$_TOML_US$(( 10#$seg ))" ;;
            *)
                return 1 ;;
        esac
    done
    _tl_node="$node"
}
