#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/key.sh - A string as the tail of a variable name
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer -2: depends on nothing, not even on the resolver, because the resolver
# uses it.
#
# One associative array's worth of behaviour, without the associative array. A
# POSIX shell has no `declare -A`, and every table in this library is a map
# from a string to a string: which file a module loaded from, which path a tool
# resolved to, which answer a gate gave. Each becomes one variable per entry,
# and this is what makes the entry's name.
#
# It was `_deps_key`, private to `deps.sh`, and it is here because it was never
# about tools. `use` needs the same thing for its loaded table and so does the
# gate cache, and three copies of a hex encoder is how they drift.
#
# Usage:
#   nut_key "pkg-config"   # sets _nk to enc_706b672d636f6e666967
#   nut_key "sed"          # sets _nk to sed
# =============================================================================

# A guard of its own rather than `nut_once`, which is defined by something that
# loads after this.
[ -n "${_NUTSHELL_KEY_SH:-}" ] && return 0
_NUTSHELL_KEY_SH=1

# Any string, as the tail of a variable name. One-to-one.
#
# A name that is already `[A-Za-z0-9_]` and does not begin `enc_` is used as
# itself, so `${_TOOL_PATH_jq}` and `${_TOOL_PATH_grep_pcre}` stay plain
# expansions and the sixteen modules reading them literally pay nothing.
#
# Anything else is hex-encoded whole, behind `enc_`. A name that is safe but
# begins `enc_` takes the encoded path too, which is what makes the mapping
# one-to-one: without that, a tool genuinely called `enc_706b67` would collide
# with `pkg` and one of them would read the other's path.
#
# Refusing instead was tried and was wrong. `deps_has` is documented to look up
# anything not in the eager list, and half the binaries worth asking about have
# a hyphen or a digit in them: `pkg-config`, `git-lfs`, `7z`. Refusing made
# `deps_has pkg-config` answer yes with an empty path, which is the one outcome
# that is worse than either alternative.
#[pub]
# Usage: nut_key "pkg-config" -> sets _nk to enc_706b672d636f6e666967
nut_key() {
    case "${1:-}" in
        "" ) _nk=""; return 1 ;;
        enc_* ) : ;;
        [0-9]* ) : ;;
        *[!A-Za-z0-9_]* ) : ;;
        * ) _nk="$1"; return 0 ;;
    esac
    # Bytes, not characters, and that is what `LC_ALL=C` is for.
    #
    # `printf '%d' "'c"` gives a codepoint and `%02x` is a minimum width rather
    # than a fixed one, so a character above U+00FF produces four hex digits
    # and the concatenation stops being prefix-free. `€` is `20ac`; so is a
    # space followed by `¬`. Two names, one variable, and the second reads the
    # first's path. Under `LC_ALL=C` both the character walk and the numeric
    # conversion go byte-wise, every byte is exactly two digits, and the
    # property holds.
    _nk_loc="${LC_ALL:-}"
    LC_ALL=C
    _nk="enc_"
    _nk_in="$1"
    while [ -n "$_nk_in" ]; do
        _nk_c="${_nk_in%"${_nk_in#?}"}"
        _nk_in="${_nk_in#?}"
        _nut_hex "$_nk_c"
        _nk="${_nk}${_nh}"
    done
    LC_ALL="$_nk_loc"
    [ -n "$_nk_loc" ] || unset LC_ALL
    return 0
}

# One byte as two hex digits, without a fork.
#
# It ran two command substitutions per byte, which is the pattern taken out of
# `lib/map.sh` in the same branch. The table covers what a tool name actually
# holds; anything else falls back to the fork and is rare enough not to matter.
_nut_hex() {
    case "$1" in
        -) _nh=2d ;;  .) _nh=2e ;;  +) _nh=2b ;;  '~') _nh=7e ;;
        0) _nh=30 ;;  1) _nh=31 ;;  2) _nh=32 ;;  3) _nh=33 ;;  4) _nh=34 ;;
        5) _nh=35 ;;  6) _nh=36 ;;  7) _nh=37 ;;  8) _nh=38 ;;  9) _nh=39 ;;
        a) _nh=61 ;;  b) _nh=62 ;;  c) _nh=63 ;;  d) _nh=64 ;;  e) _nh=65 ;;  f) _nh=66 ;;
        g) _nh=67 ;;  h) _nh=68 ;;  i) _nh=69 ;;  j) _nh=6a ;;  k) _nh=6b ;;  l) _nh=6c ;;
        m) _nh=6d ;;  n) _nh=6e ;;  o) _nh=6f ;;  p) _nh=70 ;;  q) _nh=71 ;;  r) _nh=72 ;;
        s) _nh=73 ;;  t) _nh=74 ;;  u) _nh=75 ;;  v) _nh=76 ;;  w) _nh=77 ;;  x) _nh=78 ;;
        y) _nh=79 ;;  z) _nh=7a ;;
        A) _nh=41 ;;  B) _nh=42 ;;  C) _nh=43 ;;  D) _nh=44 ;;  E) _nh=45 ;;  F) _nh=46 ;;
        G) _nh=47 ;;  H) _nh=48 ;;  I) _nh=49 ;;  J) _nh=4a ;;  K) _nh=4b ;;  L) _nh=4c ;;
        M) _nh=4d ;;  N) _nh=4e ;;  O) _nh=4f ;;  P) _nh=50 ;;  Q) _nh=51 ;;  R) _nh=52 ;;
        S) _nh=53 ;;  T) _nh=54 ;;  U) _nh=55 ;;  V) _nh=56 ;;  W) _nh=57 ;;  X) _nh=58 ;;
        Y) _nh=59 ;;  Z) _nh=5a ;;
        _) _nh=5f ;;
        # Anything left: a byte this table does not name. Two nested command
        # substitutions, which is two subshells per character, and the reason
        # everything above is written out.
        #
        # It used to be the only arm for a letter, so `pkg-config` cost
        # eighteen subshells to key once, on a path `deps_has` takes for every
        # tool whose name is not already a variable name. `printf` is a builtin
        # and costs nothing; the substitution around it is the fork.
        *) _nh="$(printf '%02x' "$(printf '%d' "'$1")")" ;;
    esac
}
