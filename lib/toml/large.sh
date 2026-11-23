#!/usr/bin/env bash
# nutshell/toml/large.sh - TOML as JSON for a file too large to read the slow way
# https://github.com/orgrinrt/nutshell
#
# Reading 1 MB of TOML in bash takes seconds and writing its tree as JSON a
# second more, and a tool's JSON turned into a tree and back in bash takes
# longer than either, so a large file has three ways to its JSON, and each
# prints the same text:
#
#   kept     the JSON an earlier process wrote for this very text, which is
#            only read back, `lib/toml/cache.sh`;
#   taplo    where it is the backend, its own JSON taken as it is and made
#            compact, with no tree in between, unless the file holds something
#            taplo would give otherwise;
#   floor    the reader in bash and `lib/toml/emit.sh`.
#
# What taplo would give otherwise is the ground the tree route stood on, now
# read off the JSON: a float, which it rewrites, a string that reads as a
# date-time, which it rewrites, a `null`, which has no TOML spelling, a NUL
# escape or a key holding a separator, which the floor refuses, and an integer
# past 64 bits, which taplo gives as another number. Any of them sends the file
# to the floor. Mikefarah yq never serves here: it reads 1 MB in five seconds,
# slower than the floor does.

[ -n "${_NUTSHELL_TOML_LARGE_SH:-}" ] && return 0
_NUTSHELL_TOML_LARGE_SH=1

use super::toml super::toml::cache super::toml::emit

# The size in bytes from which a file takes this path. Below it the tree route
# stands, and its tests, since a tool's start costs more than a small file does.
_TOML_JSON_LARGE=65536

# What in taplo's compact JSON is not what the floor writes, as one ERE: a
# number that is a float or an `inf` or a `nan`, a `null`, a string that is a
# date or a time whole, a NUL escape, a key with a unit or record separator in
# it. A value follows a colon, a comma or a bracket, and a string's own text
# holds no quote, so what follows one of those is a value or, at worst, text
# that reads like one, which is the floor's, only slower.
_tj_d="${_TOML_RE_DATE#^}" _tj_t="${_TOML_RE_TIME#^}"
_TJ_RE_ODD="(:|,|\\[)(-?[0-9]+[.eE]|-?(inf|nan)|null|\"${_tj_d%\$}\"|\"${_tj_t%\$}\")|\\\\u0000|\\\\u001[eEfF][^\"]*\":"
unset _tj_d _tj_t

# Usage: _tj_large <file> -> the file's JSON printed, rc 0; rc 3 where the file is not
# for this path and the usual one goes on; rc 2 and the reason where it is not TOML
#[pub(super)]
_tj_large() {
    local f="$1" c="" rc LC_ALL=C
    [[ -f "$f" && -r "$f" ]] || return 3
    ! IFS= read -r -d '' c < "$f" || return 3
    (( ${#c} >= _TOML_JSON_LARGE )) || return 3
    if ! _toml_jcache_load "$f" "$c"; then
        if ! _tj_tool "$c"; then
            _toml_read_floor "$f" || return $?
            _toml_emit_json || { printf 'toml: %s: %s\n' "$f" "$_tj_err" >&2; return 2; }
        fi
        _toml_jcache_store "$f" "$c" "$_tj_json"
    fi
    printf '%s\n' "$_tj_json"
}

# _tj_tool <text> -> `_tj_json`, the text as taplo's compact JSON; rc 1 where
# taplo is not the backend, refuses the text, or gives something the floor
# writes otherwise
_tj_tool() {
    local body="$1"
    [[ -z "${_TOML_FLOOR_ONLY:-}" ]] || return 1
    _toml_bom_cut body
    _toml_taplo_compact "$body" || return 1
    [[ "$_tt_json" =~ $_TJ_RE_ODD ]] && return 1
    _tj_same_wide "$1" "$_tt_json" || return 1
    _tj_json="$_tt_json"
}

# _tj_same_wide <text> <json> -> rc 0 where every number the text writes with
# 19 digits or more, or as a wide hex, octal or binary, is there in the JSON as
# the same text, in the same order, and no more of them: a number past 64 bits is
# not refused by every tool, taplo gives -9223372036854775809 as 0, and the
# digits of a digest inside a string are the same in both. At most 16 are looked
# at, and a file holding more is the floor's.
_tj_same_wide() {
    local a b
    _tj_wide "$1" || return 1
    a="$_tj_w"
    _tj_wide "$2" || return 1
    b="$_tj_w"
    [[ "$a" == "$b" ]]
}

# _tj_wide <text> -> `_tj_w`, each wide number in it and a line end after each; rc 1 past 16
_tj_wide() {
    local rest="$1" n=0 m
    _tj_w=""
    while [[ "$rest" =~ $_TOML_RE_WIDE ]]; do
        (( ++n <= 16 )) || return 1
        m="${BASH_REMATCH[0]}"
        _tj_w+="$m"$'\n'
        rest="${rest/"$m"/ }"
    done
}
