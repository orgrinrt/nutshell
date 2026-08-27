#!/bin/sh
# =============================================================================
# nutshell/lib/map.sh - A keyed table, in POSIX sh
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The floor. `lib/map.bash.sh` is the same surface over `declare -A` and is
# what bash 4 gets; this is what a POSIX shell gets, and POSIX has no
# associative array at all.
#
# A map is a name the caller holds. `map_new counts` and then `map_set counts
# hits 1`, the way `declare -A counts` would.
#
# **The key becomes part of a variable name**, which is the only keyed storage
# a POSIX shell has, so it has to be encoded: nutshell's own keys look like
# `lib/some-module.sh:412` and none of `/`, `-`, `.` or `:` may appear in a
# name. Encoded here rather than by the caller, because a caller that forgets
# gets a variable it did not mean to set.
#
# The encoding is a loop rather than `${k//[^A-Za-z0-9_]/_}`, which is bash,
# and rather than `tr`, which is a fork per key and would cost more than the
# whole operation. `benches/maps` prices what that costs against `declare -A`.
#
# It is one-to-one, not lossy: a substitution mapping every unsafe character to
# `_` collides `a.b` with `a_b`, and a map whose keys collide is worse than no
# map. Each unsafe character becomes `_xx` with its hex code, and `_` itself
# becomes `_5f` so nothing else can produce it.
#
# Usage:
#   use map
#
#   map_new counts
#   map_set counts "lib/x.sh:1" hello
#   map_get counts "lib/x.sh:1"      -> hello
#   map_has counts "nope"            -> returns 1
#   map_keys counts                  -> one key per line
# =============================================================================

[ -n "${_NUTSHELL_MAP_SH:-}" ] && return 0
_NUTSHELL_MAP_SH=1

# A name safe to build a variable out of, and safe to assign through.
#
# Every function here puts its first argument into an `eval`, because that is
# how a named container works without associative arrays. So a name that is not
# a name is code, and `map_new "m=1; echo hi; :"` would run it. Refused rather
# than encoded: a container name is written by the programmer, never taken from
# data, so there is nothing here to escape and a refusal is the honest answer.
_map_name_ok() {
    case "${1:-}" in
        "" | *[!A-Za-z0-9_]* ) return 1 ;;
        [0-9]* ) return 1 ;;
    esac
    return 0
}

# A key as the tail of a variable name. One-to-one.
#
# Walks the string a character at a time with parameter expansion only. There
# is no global substitution in POSIX and no way to iterate a string without
# either this or a fork, and a fork per key is not a map, it is a syscall
# storm.
_map_encode() {
    _me_in="$1"; _me_out=""
    while [ -n "$_me_in" ]; do
        # The whole leading run of safe characters in one expansion, rather
        # than a loop iteration per character. `lib/some-module.sh:412` has
        # five unsafe characters in twenty-two, so this is six passes instead
        # of twenty-two, and a key that needs no encoding at all leaves on the
        # first one.
        _me_run="${_me_in%%[!A-Za-z0-9]*}"
        if [ "$_me_run" = "$_me_in" ]; then
            _me_out="${_me_out}${_me_in}"
            break
        fi
        _me_out="${_me_out}${_me_run}"
        _me_in="${_me_in#"$_me_run"}"
        # `_` is encoded too, so `_` cannot be produced two ways and two
        # different keys cannot land on one name.
        _map_hex "${_me_in%"${_me_in#?}"}"
        _me_out="${_me_out}_${_mh}"
        _me_in="${_me_in#?}"
    done
    # No `printf` and no substitution at the call sites: the answer is left in
    # `_me_out` and read from there. A fork per operation is what `benches/maps`
    # measured as costing more than the substitution technique itself does.
}


# One character as two hex digits, without a fork.
#
# `printf '%d' "'c"` is POSIX: a leading quote makes printf take the character's
# value. The table below is the low half of ASCII, which is every character a
# key here can hold; anything above it falls back to the arithmetic form.
_map_hex() {
    case "$1" in
        '_') _mh=5f ;;  '/') _mh=2f ;;  '.') _mh=2e ;;
        '-') _mh=2d ;;  ':') _mh=3a ;;  ' ') _mh=20 ;;
        '=') _mh=3d ;;  ',') _mh=2c ;;  '+') _mh=2b ;;
        '@') _mh=40 ;;  '#') _mh=23 ;;  '%') _mh=25 ;;
        *)   _mh="$(printf '%02x' "$(printf '%d' "'$1")")" ;;
    esac
}


#[pub]
# Start a map, or empty one that is already there.
# Usage: map_new counts
map_new() {
    _map_name_ok "${1:-}" || return 1
    [ -n "${1:-}" ] || return 1
    map_clear "$1"
    eval "_map_keys_$1=''"
}

#[pub]
# Forget every key in a map.
# Usage: map_clear counts
map_clear() {
    _map_name_ok "${1:-}" || return 1
    [ -n "${1:-}" ] || return 1
    _mc_k=""
    eval "_mc_all=\"\${_map_keys_$1:-}\""
    for _mc_k in $_mc_all; do
        # Both, because the presence table is what `map_has` and `map_set`
        # read. Unsetting only the value left the key present but unlisted: the
        # order list was empty so `map_len` said zero, `map_set` saw the key as
        # already there and did not re-add it, and `map_get` still answered.
        # A key `map_get` returns and `map_len` cannot count.
        eval "unset _map_v_$1_$_mc_k _map_set_$1_$_mc_k"
    done
    eval "_map_keys_$1=''"
}

#[pub]
# Put a value under a key.
# Usage: map_set counts "lib/x.sh:1" hello
map_set() {
    _map_name_ok "${1:-}" || return 1
    [ -n "${1:-}" ] && [ $# -ge 2 ] || return 1
    _ms_n="$1"; _map_encode "$2"; _ms_e="$_me_out"; _ms_v="${3:-}"
    # The key list only grows when the key is new, so setting twice does not
    # list it twice and `map_len` does not drift from what is there.
    if ! eval "[ -n \"\${_map_set_${_ms_n}_${_ms_e}:-}\" ]"; then
        eval "_map_keys_${_ms_n}=\"\${_map_keys_${_ms_n}:-} ${_ms_e}\""
        eval "_map_set_${_ms_n}_${_ms_e}=1"
    fi
    eval "_map_v_${_ms_n}_${_ms_e}=\"\$_ms_v\""
}

#[pub]
# What is under a key, or nothing.
# Usage: map_get counts "lib/x.sh:1" -> hello
map_get() {
    _map_name_ok "${1:-}" || return 1
    [ -n "${1:-}" ] && [ $# -ge 2 ] || return 1
    _map_encode "$2"; _mg_e="$_me_out"
    eval "printf '%s' \"\${_map_v_$1_${_mg_e}:-}\""
}

#[pub]
# What is under a key, into a variable of your naming.
#
# `map_get` prints, so reading one value costs the caller a fork, and
# `benches/maps` measured a fork per operation as costing more than the whole
# substitution technique does. This is the same read with the answer left in a
# variable instead, and `benches/map-api` prices the difference.
#
# Usage: map_read v counts "lib/x.sh:1"; printf '%s' "$v"
map_read() {
    _map_name_ok "${1:-}" && _map_name_ok "${2:-}" || return 1
    [ $# -ge 3 ] || return 1
    _map_encode "$3"; _mr_e="$_me_out"
    eval "$1=\"\${_map_v_$2_${_mr_e}:-}\""
}

#[pub]
# Is the key there at all. Distinct from an empty value.
# Usage: map_has counts "lib/x.sh:1" -> returns 0 when set
map_has() {
    _map_name_ok "${1:-}" || return 1
    [ -n "${1:-}" ] && [ $# -ge 2 ] || return 1
    _map_encode "$2"; _mh_e="$_me_out"
    eval "[ -n \"\${_map_set_$1_${_mh_e}:-}\" ]"
}

#[pub]
# Forget one key.
# Usage: map_del counts "lib/x.sh:1"
map_del() {
    _map_name_ok "${1:-}" || return 1
    [ -n "${1:-}" ] && [ $# -ge 2 ] || return 1
    _md_n="$1"; _map_encode "$2"; _md_e="$_me_out"
    eval "[ -n \"\${_map_set_${_md_n}_${_md_e}:-}\" ]" || return 0
    eval "unset _map_v_${_md_n}_${_md_e} _map_set_${_md_n}_${_md_e}"
    _md_new=""
    eval "_md_all=\"\${_map_keys_${_md_n}:-}\""
    for _md_k in $_md_all; do
        [ "$_md_k" = "$_md_e" ] && continue
        _md_new="${_md_new} ${_md_k}"
    done
    eval "_map_keys_${_md_n}=\"\$_md_new\""
}

#[pub]
# How many keys are set.
# Usage: map_len counts -> 3
map_len() {
    _map_name_ok "${1:-}" || return 1
    [ -n "${1:-}" ] || return 1
    eval "_ml_all=\"\${_map_keys_$1:-}\""
    _ml_n=0
    for _ml_k in $_ml_all; do _ml_n=$(( _ml_n + 1 )); done
    printf '%s' "$_ml_n"
}

#[pub]
# Every key, one per line, in the order they were first set.
#
# Decoded back, because the caller put a key in and expects the same one out.
# Usage: map_keys counts
map_keys() {
    _map_name_ok "${1:-}" || return 1
    [ -n "${1:-}" ] || return 1
    eval "_mk_all=\"\${_map_keys_$1:-}\""
    for _mk_k in $_mk_all; do
        _map_decode "$_mk_k"
        printf '\n'
    done
}

# The encoding, backwards.
# The reverse of `_map_hex`, and it does not fork either.
#
# It ran two command substitutions per encoded character, which for keys of
# nutshell's own `<path>:<line>` shape is about ten forks per key: `map_keys`
# over two hundred of them took about a second under dash where plain keys took
# none. This file's own header says the encoding must not fork, in those words,
# and the decoder was doing it twice per character.
#
# The table covers what `_map_hex` produces by name. Anything else falls back
# to the fork, which is correct for a key holding a character nobody listed and
# is rare enough not to matter.
_map_unhex() {
    case "$1" in
        5f) _mu='_' ;;  2f) _mu='/' ;;  2e) _mu='.' ;;
        2d) _mu='-' ;;  3a) _mu=':' ;;  20) _mu=' ' ;;
        3d) _mu='=' ;;  2c) _mu=',' ;;  2b) _mu='+' ;;
        40) _mu='@' ;;  23) _mu='#' ;;  25) _mu='%' ;;
        *)  _mu="$(printf "\\$(printf '%03o' "0x$1")")" ;;
    esac
}

_map_decode() {
    _md2_in="$1"; _md2_out=""
    while [ -n "$_md2_in" ]; do
        _md2_c="${_md2_in%"${_md2_in#?}"}"
        if [ "$_md2_c" = "_" ]; then
            _md2_in="${_md2_in#?}"
            _md2_h="${_md2_in%"${_md2_in#??}"}"
            _md2_in="${_md2_in#??}"
            _map_unhex "$_md2_h"
            _md2_out="${_md2_out}${_mu}"
        else
            # The whole run up to the next escape in one expansion, rather than
            # a character per iteration, the same way `_map_encode` takes its
            # safe runs.
            _md2_run="${_md2_in%%_*}"
            if [ "$_md2_run" = "$_md2_in" ]; then
                _md2_out="${_md2_out}${_md2_in}"
                break
            fi
            _md2_out="${_md2_out}${_md2_run}"
            _md2_in="${_md2_in#"$_md2_run"}"
        fi
    done
    printf '%s' "$_md2_out"
}

