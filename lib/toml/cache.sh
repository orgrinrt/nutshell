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
# A kept tree is shell, and the reader runs it, so it is taken only where the
# file and its directory are the reader's own and nobody else can write either:
# anything else is code somebody else chose. Kept under
# `$XDG_CACHE_HOME/nutshell/toml`, or `$HOME/.cache/nutshell/toml`, beside
# `checkcache`'s, and written under a umask of 077. With neither variable there
# is no directory that is the reader's own, so nothing is kept or taken. Where
# the cache cannot be written, or a kept tree cannot be trusted or is cut
# short, the file is parsed as before and nothing is said: the cache saves time
# and is never needed for an answer.

[ -n "${_NUTSHELL_TOML_CACHE_SH:-}" ] && return 0
_NUTSHELL_TOML_CACHE_SH=1

use key super::toml::impl::bash

_TOML_CACHE_FLOOR="${BASH_SOURCE[0]%/*}/impl"
_TOML_CACHE_SELF="${BASH_SOURCE[0]}"

# _toml_cache_at <file> -> `_tca`, where the tree of a file is kept; rc 1 where
# it has no place
_toml_cache_at() {
    local f="$1" root
    _tca=""
    if [[ "${XDG_CACHE_HOME:-}" == /* ]]; then root="$XDG_CACHE_HOME"
    elif [[ "${HOME:-}" == /* ]]; then root="${HOME}/.cache"
    else return 1
    fi
    [[ "$f" == /* ]] || f="${PWD}/${f}"
    nut_key "$f" || return 1
    _tca="${root}/nutshell/toml/${_nk}"
}

# What parsed a kept tree: the floor's directory and the bash that ran it.
_toml_cache_by() { _tcb="${_TOML_CACHE_FLOOR}|${BASH_VERSION}"; }

# _toml_cache_trusted <file> -> rc 0 where the file and its directory are the
# reader's own, neither is a link, and neither is group- or other-writable
# Ownership is bash's own test; the mode has no builtin, and `find -perm` is
# the POSIX spelling of it. A `find` that fails trusts nothing.
_toml_cache_trusted() {
    local d="${1%/*}" open
    [[ -f "$1" && ! -L "$1" && ! -L "$d" && -O "$1" && -O "$d" ]] || return 1
    open="$(find "$d" "$1" -prune \( -perm -020 -o -perm -002 \) -print 2>/dev/null)" || return 1
    [[ -z "$open" ]]
}

# The tree kept for a file's text, put in place of the one the floor holds.
# Usage: _toml_cache_load <file> <text> -> 0 with the tree of that text in place, 1 where
# none is kept for it
#[pub(super)]
_toml_cache_load() {
    local f="$1" _tc_src="$2" _tcb _tca body g
    _toml_cache_at "$f" || return 1
    [[ -r "$_tca" ]] || return 1
    for g in "${_TOML_CACHE_FLOOR}/bash.sh" "${_TOML_CACHE_FLOOR}/bash_lex.sh" \
        "${_TOML_CACHE_FLOOR}/bash_path.sh" "$_TOML_CACHE_SELF"; do
        [[ "$_tca" -nt "$g" ]] || return 1
    done
    _toml_cache_trusted "$_tca" || return 1
    _toml_cache_by
    local _tc_by="$_tcb"
    IFS= read -r -d '' body < "$_tca"
    # The first line returns from here where the text or the parser differ,
    # before a single array is touched. One cut short or garbled stops part of
    # the way, quietly, and the tree it left half in place is no file's.
    eval "$body" 2>/dev/null || { _TOML_ID=""; return 1; }
    _TOML_ID="$f" _TOML_SRC="$_tc_src" _TOML_RC=0 _TOML_ERR=""
    return 0
}

# The tree now in place, kept for the next process that reads the same text.
# Usage: _toml_cache_store <file> <text> -> 0 always; the cache is never needed for an answer
# Written beside its place and moved in, so a reader never sees half of one,
# in a subshell for its umask: the load trusts nothing others can write.
#[pub(super)]
_toml_cache_store() {
    local f="$1" src="$2" _tcb _tca tmp a k
    _toml_cache_at "$f" || return 0
    _toml_cache_by
    tmp="${_tca}.${BASHPID:-$$}"
    (
        umask 077
        [[ -d "${_tca%/*}" ]] || mkdir -p "${_tca%/*}" || exit 0
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
        } > "$tmp" || { rm -f "$tmp"; exit 0; }
        mv -f "$tmp" "$_tca" || rm -f "$tmp"
    ) 2>/dev/null
    return 0
}
