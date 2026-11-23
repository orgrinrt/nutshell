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

use super::toml super::toml::impl::bash super::toml::emit super::toml::large

#[pub]
# Convert a TOML file to JSON, compact, keys in the order the file gives them.
#
# It writes the tree the reader built, so it is right on everything the reader
# reads: tables nest however the file reaches them, an array of tables is an
# array of objects, an inline table is an object, a dotted key is the nesting
# it spells, and every string is the decoded value escaped once for JSON.
# Every scalar is the text `lib/toml.sh` names canonical: an integer in
# decimal, a float as the file spelled it and a JSON number still, so `3.0`
# stays a float, and a date or a time a string in RFC 3339 spelling.
#
# A file the reader refuses is refused here, rc 2 with its reason. So is an
# infinity or a NaN, which TOML has and JSON has no spelling for.
# A file named `-` is the text on standard input, which the floor reads whole and
# a backend never sees, since there is no file to key a kept tree by: it is not
# cached, and the tree it leaves is dropped so the next read starts clean.
#
# A file of `_TOML_JSON_LARGE` bytes or more, 4 KB, takes the path of
# `lib/toml/large.sh`: the JSON an earlier process kept for the same text, or
# taplo's JSON where it holds nothing taplo would rewrite, else the floor.
# Every path prints the same text.
# Usage: toml_to_json "file.toml" -> prints JSON, `-` reads standard input
toml_to_json() {
    local file="${1:-}" rc=0
    [[ -n "$file" ]] || return 1
    if [[ "$file" == - ]]; then
        _tj_stdin || return $?
    else
        _tj_large "$file" || rc=$?
        (( rc == 3 )) || return "$rc"
        rc=0
        _toml_open_values "$file" || return $?
    fi
    # A value the tool rewrote, `_TOML_JL` of them, is the floor's to write.
    if [[ "$_TOML_FROM" == json ]] && (( ${_TOML_JL:-0} )); then
        _TOML_FROM=bash
        _toml_open "$file" || return $?
    fi
    _toml_emit_json || rc=$?
    if (( rc != 0 )); then
        printf 'toml: %s: %s\n' "$file" "$_tj_err" >&2
        return 2
    fi
    printf '%s\n' "$_tj_json"
}

# _tj_stdin -> the tree of standard input's text, rc 2 and the reason where it is not TOML
_tj_stdin() {
    local c=""
    if IFS= read -r -d '' c; then
        printf 'toml: -: the text holds a NUL byte\n' >&2
        return 2
    fi
    _TOML_ID="" _TOML_FROM=bash
    _toml_parse_text "-" "$c" || { printf '%s\n' "$_TOML_ERR" >&2; return 2; }
}
