#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/cache.sh - the floor's tree, kept between processes
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Part of `toml`. The floor parses a file into a tree once per process; this
# keeps that tree for the next process that reads the same text. The engine pin
# and the `[deps.paths]` pins each read a manifest before a script's first line,
# and parsing a 332-line one in bash is about 37ms, every start.
#
# Keyed by the file's path and checked against its text, not its mtime: the
# kept tree carries the text it was parsed from and is used only where the file
# still holds exactly that text, so a file replaced with an older mtime, which
# `tar -x` and `rsync -a` both do, is parsed again. It also carries which floor
# and which bash parsed it, and it is not used where the floor's files are newer
# than it, so a changed parser never answers from an older one's tree.
#
# Kept under `$XDG_CACHE_HOME/nutshell/toml`, beside `checkcache`'s. Where that
# cannot be written the file is parsed as before and nothing is said: the cache
# saves time and is never needed for an answer.
# =============================================================================

[ -n "${_NUTSHELL_TOML_CACHE_SH:-}" ] && return 0
_NUTSHELL_TOML_CACHE_SH=1

use super::toml::impl::bash

_TOML_CACHE_FLOOR="${BASH_SOURCE[0]%/*}/impl"

# _toml_cache_at <file> -> `_tca`, where the tree of a file is kept; rc 1 where
# it has no place
_toml_cache_at() {
    local f="$1"
    _tca=""
    [[ "$f" == /* ]] || f="${PWD}/${f}"
    nut_key "$f" || return 1
    _tca="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/nutshell/toml/${_nk}"
}

# What parsed a kept tree: the floor's directory and the bash that ran it.
_toml_cache_by() { _tcb="${_TOML_CACHE_FLOOR}|${BASH_VERSION}"; }

# _toml_cache_load <file> <text> -> 0 with the tree of that text in place, 1 where
# none is kept for it
#[pub(super)]
_toml_cache_load() {
    local f="$1" _tc_src="$2" _tcb _tca body g
    _toml_cache_at "$f" || return 1
    [[ -r "$_tca" ]] || return 1
    for g in bash.sh bash_lex.sh bash_path.sh; do
        [[ "$_tca" -nt "${_TOML_CACHE_FLOOR}/${g}" ]] || return 1
    done
    _toml_cache_by
    local _tc_by="$_tcb"
    IFS= read -r -d '' body < "$_tca"
    # The first line returns from here where the text or the parser differ,
    # before a single array is touched.
    eval "$body" || return 1
    _TOML_ID="$f" _TOML_SRC="$_tc_src" _TOML_RC=0 _TOML_ERR=""
    return 0
}

# _toml_cache_store <file> <text>: the tree now in place, kept for that text.
# Written beside its place and moved in, so a reader never sees half of one.
#[pub(super)]
_toml_cache_store() {
    local f="$1" src="$2" _tcb _tca tmp a k
    _toml_cache_at "$f" || return 0
    _toml_cache_by
    [[ -d "${_tca%/*}" ]] || mkdir -p "${_tca%/*}" 2>/dev/null || return 0
    tmp="${_tca}.$$"
    {
        printf '[[ "$_tc_by" == %q && "$_tc_src" == %q ]] || return 1\n' "$_tcb" "$src"
        for a in _TOML_T _TOML_V _TOML_R _TOML_K _TOML_N _TOML_F _TOML_W _TOML_P _TOML_C _TOML_E; do
            local -n _tcs_arr="$a"
            printf '%s=(' "$a"
            for k in "${!_tcs_arr[@]}"; do
                printf '[%q]=%q ' "$k" "${_tcs_arr[$k]}"
            done
            printf ')\n'
            unset -n _tcs_arr
        done
        printf '_TOML_HDR=('
        for k in "${_TOML_HDR[@]}"; do printf '%q ' "$k"; done
        printf ')\n'
    } > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 0; }
    mv -f "$tmp" "$_tca" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    return 0
}
