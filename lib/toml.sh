#!/usr/bin/env bash
# =============================================================================
# nutshell/core/toml.sh - TOML parsing
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on validate.sh
#
# The TOML API. `use toml` and call it. The values come from the best reader
# `deps` finds, picked at the first call: taplo where it prints TOML as JSON, else
# mikefarah yq where it reads TOML, else the bash floor in
# `lib/toml/impl/bash.sh`, which reads TOML 1.0 in full or refuses the file and
# needs nothing. Never the python yq. A tool turns the file into JSON once per
# process, kept while the file's text is unchanged, and every reader answers
# from the tree of it through one path language.
#
# JSON has the values and not how the file wrote them, so whatever turns on
# that, a table's header or an inline table, `[[x]]` or an array of inline
# tables, header order, the text of an array as written, is answered by the
# floor, and so is any file a tool refuses: the floor then reads it or names
# why not. Writing is the floor's line editor in `lib/toml/write.sh` whatever
# reads.
#
# One path language for every function that takes one, the same as json's:
# `a.b.0.c`, where a dot separates segments, a numeric segment indexes an
# array or an array of tables, and `"quoted.key"` in double quotes is one
# segment.
#
# Return codes, everywhere: 0 found, 1 not there (no file, no such key), 2 the
# file is not TOML this reader accepts, with the line and the construct on
# stderr. A refusal is never reported as a miss.

# Prevent multiple inclusion
# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE`
# and so needs bash. Under a POSIX shell it is not found, the
# `|| return 0` beside it fires on every load, and the module reports
# success having defined nothing.
[ -n "${_NUTSHELL_TOML_SH:-}" ] && return 0
_NUTSHELL_TOML_SH=1

# Declared, not sourced by path. A hand-rolled `source` loads the module and
# hides it from the module-contract check, which reads `use` lines, so the
# dependency would be real and unrecorded at once.
use validate
use deps
use super::toml::impl::bash super::toml::impl::bash_path super::toml::impl::from_json

_TOML_BACKEND=""
_TOML_FROM=""
_TOML_RE_WIDE='0x(_?[0-9A-Fa-f]){16}|0o(_?[0-7]){21}|0b(_?[01]){63}|[0-9](_?[0-9]){18}'

# -----------------------------------------------------------------------------
# Internal helpers

# _toml_node_show <node> -> `_tn_out`, the path that names a node
_toml_node_show() {
    local rest="${1#R}" seg
    _tn_out=""
    rest="${rest#"$_TOML_US"}"
    [[ -n "$rest" ]] || return 0
    while :; do
        seg="${rest%%"$_TOML_US"*}"
        _toml_seg_show "$seg"
        _tn_out+="${_tn_out:+.}${_ts_out}"
        [[ "$rest" == *"$_TOML_US"* ]] || return 0
        rest="${rest#*"$_TOML_US"}"
    done
}

# _toml_text <node> -> `_tx_out`, a value as text; rc 1 for a table or an
# array of tables, which have none
# A scalar is its value, decoded. An array or an inline table is what the file
# wrote, so it can be read again by `toml_inline_get` or split by `toml_array`.
_toml_text() {
    local node="$1" i n
    case "${_TOML_T[$node]-}" in
        ''|aot)
            return 1 ;;
        table)
            [[ "${_TOML_F[$node]-}" == *X* && -n "${_TOML_R[$node]+x}" ]] || return 1
            _tx_out="${_TOML_R[$node]}" ;;
        array)
            _tx_out="${_TOML_R[$node]}"
            [[ "$_tx_out" == *$'\n'* ]] || return 0
            # Written over several lines: given back on one, element by element.
            n="${_TOML_N[$node]}"
            _tx_out="["
            for (( i = 0; i < n; i++ )); do
                (( i )) && _tx_out+=", "
                _tx_out+="${_TOML_R[$node$_TOML_US$i]}"
            done
            _tx_out+="]" ;;
        *)
            _tx_out="${_TOML_V[$node]}" ;;
    esac
}

# _toml_open <file> -> the file read; rc 2 also prints why
_toml_open() {
    local rc=0
    _toml_load "$1" || rc=$?
    (( rc == 2 )) && printf '%s\n' "$_TOML_ERR" >&2
    return "$rc"
}

# _toml_tool_json <text> -> `_tt_json`, the text as JSON from the backend
# The stub `nut_lazy_guard` keeps: the first call picks the backend, whose
# module rebinds this name, and calls it. Where only the floor serves, it is
# rebound to rc 3, no JSON. In this shell, never a subshell, or the pick is
# lost with it and made again on every call.
_toml_tool_json() {
    nut_lazy_guard _toml_tool_json || return 1
    local _NUT_LAZY__toml_tool_json=1
    # FIXME(63ac7b74f97a): the variant stands in for `deps_can toml_json_taplo`
    # and `deps_can toml_read`, which scan every tool first, 200 ms on the first
    # read; a tool that then fails on a file sends it to the floor all the same.
    if [[ "$(deps_variant taplo)" == taplo ]]; then
        _TOML_TOOL="$(deps_path taplo)"
        nut_reload super::toml::impl::taplo
        _TOML_BACKEND=taplo
    elif [[ "$(deps_variant yq)" == mikefarah ]]; then
        # FIXME(1d1168da9656): mikefarah yq 4.44.3 reads a key or a table
        # defined twice instead of refusing the file, so where it is the only
        # tool an invalid file reads; taplo goes first for that.
        _TOML_TOOL="$(deps_path yq)"
        nut_reload super::toml::impl::yq
        _TOML_BACKEND=yq
    else
        _toml_tool_json() { return 3; }
        _TOML_BACKEND=bash
    fi
    _toml_tool_json "$@"
}

# _toml_open_values <file> -> the file read for its values, codes as `_toml_open`
# The tree of the backend's JSON, made once while the file's text is the same.
# The floor's tree where that is loaded already for the same text, since it
# answers everything, or where the backend cannot serve. `_TOML_FROM` says
# which, `json` or `bash`. Where `_TOML_FLOOR_ONLY` is set, the floor alone: deps
# sets it to read its own pins, since a backend is picked by asking deps.
_toml_open_values() {
    local f="$1" c=""
    [[ -f "$f" && -r "$f" ]] || return 1
    _TOML_FROM=bash
    [[ -z "${_TOML_FLOOR_ONLY:-}" ]] || { _toml_open "$f"; return; }
    IFS= read -r -d '' c < "$f" && { _toml_open "$f"; return; }
    [[ "$_TOML_ID" == "$f" && "$_TOML_SRC" == "$c" ]] && { _toml_open "$f"; return; }
    _TOML_FROM=json
    [[ "$_TOML_ID" == "json$_TOML_US$f" && "$_TOML_SRC" == "$c" ]] && return 0
    # A number past 64 bits is not refused by every tool: taplo gives
    # -9223372036854775809 as 0. A file that may hold one goes to the floor.
    [[ "$c" =~ $_TOML_RE_WIDE ]] && { _TOML_FROM=bash; _toml_open "$f"; return; }
    _TOML_ID=""
    if _toml_tool_json "${c#$'\xef\xbb\xbf'}" && _toml_json_tree "$f" "$_tt_json"; then
        _TOML_ID="json$_TOML_US$f" _TOML_SRC="$c" _TOML_RC=0
        return 0
    fi
    _TOML_FROM=bash
    _toml_open "$f"
}

# _toml_full <file> -> where the tree is the backend's, the floor's instead, and
# `_tl_node` found again in it, for an answer that turns on how the file wrote it
_toml_full() {
    [[ "$_TOML_FROM" == json ]] || return 0
    _TOML_FROM=bash
    _toml_open "$1" || return $?
    _toml_lookup
}

# _toml_children <node> -> `_tc_keys`, the keys of a table in file order
_toml_children() {
    local k="${_TOML_K[$1]-}"
    _tc_keys=()
    [[ -n "$k" ]] || return 0
    k="${k#"$_TOML_RS"}"
    while :; do
        _tc_keys+=("${k%%"$_TOML_RS"*}")
        [[ "$k" == *"$_TOML_RS"* ]] || return 0
        k="${k#*"$_TOML_RS"}"
    done
}

# -----------------------------------------------------------------------------
# Public API

#[pub]
# Get a value from a TOML file.
#
# The path reaches a key under a header, a dotted key, a key inside an inline
# table and an element of an array alike. A string comes back decoded, a
# number in decimal, an array or an inline table as written. A table that is
# not inline, and an array of tables, have no value: `toml_keys` and
# `toml_tables` read those.
# Usage: toml_get "file.toml" "section.key" -> prints the value
toml_get() {
    _toml_value "${1:-}" "${2:-}" || return $?
    printf '%s\n' "$_tx_out"
}

# _toml_value <file> <path> -> `_tx_out`, what `toml_get` prints, in this shell
# so the backend picked and the tree read outlive the call
_toml_value() {
    local file="$1" key="$2"
    [[ -n "$file" && -n "$key" ]] || return 1
    _toml_open_values "$file" || return $?
    _toml_path_split "$key" || return 1
    _toml_lookup || return 1
    # Only a scalar is the same whoever read it; anything else is given as the
    # file wrote it, or not at all, which the floor knows.
    case "${_TOML_T[$_tl_node]}" in
        table|array|aot) _toml_full "$file" || return $? ;;
    esac
    _toml_text "$_tl_node"
}

#[pub]
# Get a value with a default if not found
# Usage: toml_get_or "file.toml" "key" "default" -> prints the value, or the default when the key is absent
toml_get_or() {
    local file="${1:-}" key="${2:-}" default="${3:-}" rc=0
    toml_get "$file" "$key" || rc=$?
    case "$rc" in
        0) return 0 ;;
        2) return 2 ;;
    esac
    printf '%s\n' "$default"
}

#[pub]
# Check if a key exists in a TOML file
# Usage: toml_has "file.toml" "key" -> returns 0 (true), 1 (false), 2 (not TOML)
toml_has() {
    toml_get "${1:-}" "${2:-}" >/dev/null
}

#[pub]
# List the tables named by a header, in the order the file first names them.
# An array of tables is listed once, and a table under one of its elements by
# the element's index, `servers.0.opts`.
# Usage: toml_sections "file.toml" -> prints section names, one per line
toml_sections() {
    local file="${1:-}" node
    _toml_open "$file" || return $?
    for node in "${_TOML_HDR[@]}"; do
        _toml_node_show "$node"
        printf '%s\n' "$_tn_out"
    done
}

#[pub]
# List the keys that hold values in a table, the root when none is named.
# A table that has a header of its own is a section rather than a key.
# Usage: toml_keys "file.toml" [section] -> prints one key per line, root keys when no section is named
toml_keys() {
    local file="${1:-}" section="${2:-}" node k child f
    _toml_open "$file" || return $?
    node=R
    if [[ -n "$section" ]]; then
        _toml_path_split "$section" || return 1
        _toml_lookup || return 1
        node="$_tl_node"
    fi
    [[ "${_TOML_T[$node]}" == table ]] || return 1
    _toml_children "$node"
    for k in "${_tc_keys[@]}"; do
        child="$node$_TOML_US$k"
        f="${_TOML_F[$child]-}"
        [[ "${_TOML_T[$child]}" == aot ]] && continue
        [[ "${_TOML_T[$child]}" == table && "$f" != *[dX]* ]] && continue
        printf '%s\n' "$k"
    done
}

#[pub]
# Whether a path names a table or an array of tables.
# `[a.b.c]` creates `a` and `a.b` per TOML v1.0.0, so both answer true here,
# which is what `toml_subsections` lists. An inline table is a value, not a
# section.
# Usage: toml_has_section "file.toml" "server" -> returns 0 (true) or 1 (false)
toml_has_section() {
    local file="${1:-}" section="${2:-}"
    [[ -n "$file" && -n "$section" ]] || return 1
    _toml_open "$file" || return $?
    _toml_path_split "$section" || return 1
    _toml_lookup || return 1
    case "${_TOML_T[$_tl_node]}" in
        aot) return 0 ;;
        table) [[ "${_TOML_F[$_tl_node]-}" != *X* ]] ;;
        *) return 1 ;;
    esac
}

#[pub]
# List the tables and arrays of tables directly under a table, each once.
# Usage: toml_subsections "file.toml" "kind.gpg" -> child names, one per line
toml_subsections() {
    local file="${1:-}" parent="${2:-}" k child
    [[ -n "$file" && -n "$parent" ]] || return 1
    _toml_open "$file" || return $?
    _toml_path_split "$parent" || return 1
    _toml_lookup || return 1
    [[ "${_TOML_T[$_tl_node]}" == table ]] || return 1
    _toml_children "$_tl_node"
    for k in "${_tc_keys[@]}"; do
        child="$_tl_node$_TOML_US$k"
        case "${_TOML_T[$child]}" in
            aot) ;;
            table) [[ "${_TOML_F[$child]-}" != *X* ]] || continue ;;
            *) continue ;;
        esac
        _toml_seg_show "$k"
        printf '%s\n' "$_ts_out"
    done
}

#[pub]
# Read an array into a bash array, one element each.
# A string element comes back decoded, a nested array or an inline table as
# written, which `toml_inline_get` reads further. A value that is not an array
# comes back as the one element. An array of tables has no text; `toml_tables`
# reads it.
# Usage: toml_array "file.toml" "key" arr -> fills arr, returns 1 when the key is absent
toml_array() {
    local __toml_file="${1:-}" __toml_key="${2:-}"
    local -n _arr="${3:-_toml_array_result}"
    _arr=()
    [[ -n "$__toml_file" && -n "$__toml_key" ]] || return 1
    _toml_open_values "$__toml_file" || return $?
    _toml_path_split "$__toml_key" || return 1
    _toml_lookup || return 1
    local __toml_n __toml_i
    # From the JSON only for scalars, alone or in an array, as `toml_get`.
    case "${_TOML_T[$_tl_node]}" in
        table|aot) _toml_full "$__toml_file" || return $? ;;
        array)
            __toml_n="${_TOML_N[$_tl_node]}"
            for (( __toml_i = 0; __toml_i < __toml_n; __toml_i++ )); do
                case "${_TOML_T[$_tl_node$_TOML_US$__toml_i]}" in
                    table|array|aot) _toml_full "$__toml_file" || return $?; break ;;
                esac
            done ;;
    esac
    if [[ "${_TOML_T[$_tl_node]}" == array ]]; then
        __toml_n="${_TOML_N[$_tl_node]}"
        for (( __toml_i = 0; __toml_i < __toml_n; __toml_i++ )); do
            _toml_text "$_tl_node$_TOML_US$__toml_i" || return 1
            _arr+=("$_tx_out")
        done
        return 0
    fi
    _toml_text "$_tl_node" || return 1
    _arr=("$_tx_out")
}

#[pub]
# Read a key out of an inline table given as text, as `toml_array` and
# `toml_get` hand one back. The key is one key, taken as it is, dots and all.
#
# Returns 1 when the key is absent, which is how an optional field is read:
# `type` is missing on most of a dotfiles registry's config rows and means
# file, and asking for it should say "not there" rather than print nothing and
# claim success. Returns 2 when the text is not an inline table TOML accepts.
# Usage: toml_inline_get '{ a = "1", b = "2" }' b -> prints 2
toml_inline_get() {
    local table="${1:-}" want="${2:-}" node
    [[ -n "$want" ]] || return 1
    _toml_trim_into table "$table"
    [[ "$table" == "$_TOML_LB"* ]] || return 1
    _TOML_ID=""
    if ! _toml_parse_text "inline" "_x = ${table}"; then
        printf '%s\n' "$_TOML_ERR" >&2
        return 2
    fi
    node="R${_TOML_US}_x"
    [[ "${_TOML_T[$node]}" == table ]] || return 1
    node+="$_TOML_US$want"
    [[ -n "${_TOML_T[$node]-}" ]] || return 1
    _toml_text "$node" || return 1
    printf '%s\n' "$_tx_out"
}

#[pub]
# Whether an inline table carries a key at all.
# Usage: toml_inline_has '{ a = "1" }' a -> returns 0 (true) or 1 (false)
toml_inline_has() { toml_inline_get "${1:-}" "${2:-}" >/dev/null 2>&1; }

#[pub]
# How many tables an array of tables holds.
# Fails where the path names anything other than an array of tables.
# Usage: toml_table_count "file.toml" "products" -> prints 3
toml_table_count() {
    local file="${1:-}" path="${2:-}"
    [[ -n "$file" && -n "$path" ]] || return 1
    _toml_open "$file" || return $?
    _toml_path_split "$path" || return 1
    _toml_lookup || return 1
    [[ "${_TOML_T[$_tl_node]}" == aot ]] || return 1
    printf '%s\n' "${_TOML_N[$_tl_node]}"
}

#[pub]
# The path of every table in an array of tables, one per line, each ready to
# be extended with a key and handed to `toml_get`.
# Usage: toml_tables "file.toml" "products" -> prints products.0, products.1, ...
toml_tables() {
    local file="${1:-}" path="${2:-}" i n
    [[ -n "$file" && -n "$path" ]] || return 1
    _toml_open "$file" || return $?
    _toml_path_split "$path" || return 1
    _toml_lookup || return 1
    [[ "${_TOML_T[$_tl_node]}" == aot ]] || return 1
    n="${_TOML_N[$_tl_node]}"
    for (( i = 0; i < n; i++ )); do
        printf '%s.%s\n' "$path" "$i"
    done
}

#[pub]
# Check if a TOML value is true (handles various boolean representations)
# Usage: toml_is_true "file.toml" "key" -> returns 0 (true) or 1 (false)
toml_is_true() {
    _toml_value "${1:-}" "${2:-}" || return 1
    is_truthy "$_tx_out"
}

#[pub]
# Get the keys of a table that hold values, as "key=value" lines. A table
# under it is left out, as `toml_keys` would.
# Usage: toml_section_pairs "file.toml" "section" -> prints one key=value per line, values already unquoted
toml_section_pairs() {
    local file="${1:-}" section="${2:-}" k child
    [[ -n "$file" && -n "$section" ]] || return 1
    _toml_open "$file" || return $?
    _toml_path_split "$section" || return 1
    _toml_lookup || return 1
    [[ "${_TOML_T[$_tl_node]}" == table ]] || return 1
    _toml_children "$_tl_node"
    for k in "${_tc_keys[@]}"; do
        child="$_tl_node$_TOML_US$k"
        _toml_text "$child" || continue
        printf '%s=%s\n' "$k" "$_tx_out"
    done
}
