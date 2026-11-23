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
# file and every directory from its own up to the cache root are the reader's
# own and nobody else can write any of them, and it runs what was read from the
# file that was checked: anything else is code somebody else chose. Kept under
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

# _toml_cache_at <file> -> `_tca`, where the tree of a file is kept, and `_tcr`
# the cache root it is under; rc 1 where it has no place
_toml_cache_at() {
    local f="$1" root
    _tca="" _tcr=""
    if [[ "${XDG_CACHE_HOME:-}" == /* ]]; then root="$XDG_CACHE_HOME"
    elif [[ "${HOME:-}" == /* ]]; then root="${HOME}/.cache"
    else return 1
    fi
    while [[ "$root" == ?*/ ]]; do root="${root%/}"; done
    [[ "$f" == /* ]] || f="${PWD}/${f}"
    nut_key "$f" || return 1
    _tcr="$root"
    _tca="${root}/nutshell/toml/${_nk}"
}

# What parsed a kept tree: the floor's directory and the bash that ran it.
_toml_cache_by() { _tcb="${_TOML_CACHE_FLOOR}|${BASH_VERSION}"; }

# What this process has already checked, held as open descriptors so that the
# inode checked is the one compared again: bash has no builtin that reads an
# inode number, but `-ef` on `/dev/fd/N` and the path compares device and inode.
# A directory or a kept tree swapped for another inode is not found here and is
# checked again; one that is the same inode is not. A mode changed after the
# check, by the reader's own hand, is not seen until the next process. Bounded,
# and a subshell's additions are gone with it.
declare -gA _TOML_CACHE_DIRFD=() _TOML_CACHE_FILEFD=()

# _toml_cache_held <array name> <path> -> rc 0 where <path> is still the inode
# the array holds a descriptor for
_toml_cache_held() {
    local -n _tch="$1"
    [[ -n "${_tch[$2]:-}" && "/dev/fd/${_tch[$2]}" -ef "$2" ]]
}

# _toml_cache_hold <array name> <path> <fd to duplicate | -> keeps a descriptor
# on the inode just checked, in place of one it held for that path
_toml_cache_hold() {
    local -n _tch="$1"
    local h
    [[ -z "${_tch[$2]:-}" ]] || { h="${_tch[$2]}"; exec {h}<&-; unset "_tch[$2]"; }
    (( ${#_tch[@]} < 64 )) || return 0
    if [[ "$3" == - ]]; then { exec {h}< "$2"; } 2>/dev/null || return 0
    else { exec {h}<&"$3"; } 2>/dev/null || return 0
    fi
    _tch[$2]="$h"
}

# _toml_cache_trusted <file> <fd> <root> -> rc 0 where the file open on <fd> is
# the one at <file>, and it and every directory from its own up to <root> are
# the reader's own and neither group- nor other-writable, none of them below
# the root a link
#
# The open file is what is checked, by bash's tests on `/dev/fd/N`, which bash
# answers from the descriptor itself: a plain file, the reader's, and still the
# one the path names. Its mode is read through `/proc/<pid>/fd/N` where there
# is one, else through the path, which that same-file test has just tied to it.
# A directory others can write anywhere on the way is one where the file, or a
# directory, could be swapped, so each is checked. Ownership is bash's own
# test; the mode has no builtin, and `find -perm` is the POSIX spelling of it,
# `-H` so a `/proc` entry is read as the file it opens. A `find` that fails
# trusts nothing. One `find` takes what is not already checked in this process:
# the file where this inode was not, the directories where theirs was not.
_toml_cache_trusted() {
    local p="$1" fd="/dev/fd/$2" root="$3" d open dh="" need_f=1 need_d=1
    local -a list=()
    [[ -f "$fd" && -O "$fd" && ! -L "$p" && "$fd" -ef "$p" ]] || return 1
    d="${p%/*}"
    ! _toml_cache_held _TOML_CACHE_FILEFD "$p" || need_f=0
    ! _toml_cache_held _TOML_CACHE_DIRFD "$d" || need_d=0
    (( need_f || need_d )) || return 0
    if (( need_f )); then
        if [[ -e "/proc/${BASHPID:-$$}/fd/$2" ]]; then list=("/proc/${BASHPID:-$$}/fd/$2")
        else list=("$p")
        fi
    fi
    if (( need_d )); then
        { exec {dh}< "$d"; } 2>/dev/null || return 1
        while [[ "$d" != "$root" ]]; do
            [[ "$d" == "$root"/* && -d "$d" && ! -L "$d" && -O "$d" ]] || { exec {dh}<&-; return 1; }
            list+=("$d")
            d="${d%/*}"
        done
        [[ -d "$d" && -O "$d" ]] || { exec {dh}<&-; return 1; }
        list+=("$d")
        d="${p%/*}"
    fi
    open="$(find -H "${list[@]}" -prune \( -perm -020 -o -perm -002 \) -print 2>/dev/null)" || open=x
    if [[ -n "$open" ]]; then
        [[ -z "$dh" ]] || exec {dh}<&-
        return 1
    fi
    if (( need_d )); then
        # The descriptor opened before the check, still the path's inode.
        if ! [[ "/dev/fd/$dh" -ef "$d" ]]; then exec {dh}<&-; return 1; fi
        _toml_cache_hold _TOML_CACHE_DIRFD "$d" "$dh"
        exec {dh}<&-
    fi
    (( ! need_f )) || _toml_cache_hold _TOML_CACHE_FILEFD "$p" "$2"
    return 0
}

# The tree kept for a file's text, put in place of the one the floor holds.
# Usage: _toml_cache_load <file> <text> -> 0 with the tree of that text in place, 1 where
# none is kept for it
# Read whole from one open descriptor first, then that descriptor's file
# checked, then what was read run: a tree swapped in after the check is never
# the one that runs.
#[pub(super)]
_toml_cache_load() {
    local f="$1" _tc_src="$2" _tcb _tca _tcr body g fd ok=1
    _toml_cache_at "$f" || return 1
    # A regular file and no link before the open: opening a FIFO blocks until
    # a writer comes, and a device never ends. The checks after the open still
    # catch a file swapped in between.
    [[ -f "$_tca" && ! -L "$_tca" && -r "$_tca" ]] || return 1
    for g in "${_TOML_CACHE_FLOOR}/bash.sh" "${_TOML_CACHE_FLOOR}/bash_lex.sh" \
        "${_TOML_CACHE_FLOOR}/bash_path.sh" "$_TOML_CACHE_SELF"; do
        [[ "$_tca" -nt "$g" ]] || return 1
    done
    { exec {fd}< "$_tca"; } 2>/dev/null || return 1
    IFS= read -r -d '' body <&"$fd"
    _toml_cache_trusted "$_tca" "$fd" "$_tcr" || ok=0
    exec {fd}<&-
    [[ "$ok" == 1 ]] || return 1
    _toml_cache_by
    local _tc_by="$_tcb"
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
