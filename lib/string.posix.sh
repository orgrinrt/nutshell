#!/bin/sh
# =============================================================================
# nutshell/lib/string.posix.sh - String helpers, in POSIX sh
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The floor. `lib/string.sh` is the same surface written for bash and is what
# gets sourced where bash 4 is running; this is what a POSIX shell gets, and
# before it existed a POSIX shell got a parse error and no module at all.
#
# The manifest decides between them, above the sourcing, because a file using a
# construct the running shell cannot parse fails at parse time and no `if`
# inside it can help:
#
#     #[shell(bash4)]
#     string  lib/string.sh
#     string  lib/string.posix.sh
#
# **What is missing here, and it is one thing.** `str_split` writes into an
# array through a nameref. POSIX has neither, and a version returning something
# else would be a different function wearing the same name, which is worse than
# an absent one: a caller would get an answer in the wrong shape rather than a
# clear failure. So a script wanting `str_split` wants bash, and finds out by
# the name not being there.
#
# Everything else is the same contract, checked against the bash file by a test
# that runs both and compares, rather than by reading them side by side.
#
# The two-file arrangement is deliberate over one file full of branches. A
# branch per function is a branch evaluated per call, and the whole point of
# deciding at load time is that the decision is taken once.
# =============================================================================

# `nut_once` is nutshell's, and nutshell may not be loaded: this file is meant
# to be readable by a shell that has none of it. Guarded the plain way instead.
[ -n "${_NUTSHELL_STRING_POSIX_SH:-}" ] && return 0
_NUTSHELL_STRING_POSIX_SH=1

#[allow(trivial_wrapper)]
#[pub]
# Convert string to lowercase
# Usage: str_lower "HELLO" -> "hello"
#
# `tr` rather than `${x,,}`, which is bash. There is no POSIX parameter
# expansion for case, so this is one of the few places the floor needs a tool
# at all, and `tr` is in POSIX itself rather than an optional extra.
str_lower() {
    printf '%s\n' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

#[allow(trivial_wrapper)]
#[pub]
# Convert string to uppercase
# Usage: str_upper "hello" -> "HELLO"
str_upper() {
    printf '%s\n' "${1:-}" | tr '[:lower:]' '[:upper:]'
}

#[pub]
# Trim whitespace from both ends
# Usage: str_trim "  hello  " -> "hello"
#
# The expansions here are POSIX as written: `${x#pattern}` and `${x%pattern}`
# both are, and so is a bracket expression inside one. Only `${x//}` is not.
str_trim() {
    _s="${1:-}"
    _s="${_s#"${_s%%[![:space:]]*}"}"
    _s="${_s%"${_s##*[![:space:]]}"}"
    printf '%s\n' "$_s"
}

#[pub]
# Trim whitespace from left side
# Usage: str_ltrim "  hello" -> "hello"
str_ltrim() {
    _s="${1:-}"
    printf '%s\n' "${_s#"${_s%%[![:space:]]*}"}"
}

#[pub]
# Trim whitespace from right side
# Usage: str_rtrim "hello  " -> "hello"
str_rtrim() {
    _s="${1:-}"
    printf '%s\n' "${_s%"${_s##*[![:space:]]}"}"
}

#[pub]
# Replace all occurrences of a substring
# Usage: str_replace "hello world" "world" "bash" -> "hello bash"
#
# A loop rather than `${x//from/to}`, which is bash. It walks by cutting at the
# first occurrence and keeping what is either side, which is two POSIX
# expansions and no tool: `sed` would need the needle escaped as a regular
# expression, and a caller's needle is a literal.
str_replace() {
    _str="${1:-}"; _from="${2:-}"; _to="${3:-}"
    if [ -z "$_from" ]; then printf '%s\n' "$_str"; return 0; fi

    _out=""
    while :; do
        case "$_str" in
            *"$_from"*) ;;
            *) break ;;
        esac
        _head="${_str%%"$_from"*}"
        _out="${_out}${_head}${_to}"
        _str="${_str#*"$_from"}"
    done
    printf '%s\n' "${_out}${_str}"
}

#[pub]
# Check if string contains substring
# Usage: str_contains "hello world" "world" -> returns 0 (true)
str_contains() {
    [ -z "${2:-}" ] && return 0
    case "${1:-}" in *"$2"*) return 0 ;; esac
    return 1
}

#[pub]
# Check if string starts with prefix
# Usage: str_starts_with "hello world" "hello" -> returns 0 (true)
str_starts_with() {
    [ -z "${2:-}" ] && return 0
    case "${1:-}" in "$2"*) return 0 ;; esac
    return 1
}

#[pub]
# Check if string ends with suffix
# Usage: str_ends_with "hello world" "world" -> returns 0 (true)
str_ends_with() {
    [ -z "${2:-}" ] && return 0
    case "${1:-}" in *"$2") return 0 ;; esac
    return 1
}

#[pub]
# Join arguments with a delimiter
# Usage: str_join ", " a b c -> "a, b, c"
str_join() {
    _d="${1:-}"; shift
    _r=""; _first=1
    for _item in "$@"; do
        if [ "$_first" -eq 1 ]; then _r="$_item"; _first=0
        else _r="${_r}${_d}${_item}"; fi
    done
    printf '%s\n' "$_r"
}

#[allow(trivial_wrapper)]
#[pub]
# Get string length
# Usage: str_length "hello" -> 5
str_length() {
    _s="${1:-}"
    printf '%s\n' "${#_s}"
}

#[pub]
# Extract substring
# Usage: str_substr "hello world" 0 5 -> "hello"
#
# `cut -c` rather than `${x:start:len}`, which is bash. One-based and inclusive
# where the expansion is zero-based and a length, so the arithmetic converts
# rather than the caller having to.
str_substr() {
    _s="${1:-}"; _start="${2:-0}"; _len="${3:-}"
    [ "$_start" -lt 0 ] 2>/dev/null && _start=0
    _from=$(( _start + 1 ))
    if [ -n "$_len" ]; then
        [ "$_len" -le 0 ] 2>/dev/null && { printf '\n'; return 0; }
        printf '%s\n' "$_s" | cut -c "${_from}-$(( _start + _len ))"
    else
        printf '%s\n' "$_s" | cut -c "${_from}-"
    fi
}

#[pub]
# Repeat string N times
# Usage: str_repeat "-" 5 -> "-----"
str_repeat() {
    _s="${1:-}"; _n="${2:-1}"
    [ "$_n" -le 0 ] 2>/dev/null && return 0
    _r=""; _i=0
    while [ "$_i" -lt "$_n" ]; do _r="${_r}${_s}"; _i=$(( _i + 1 )); done
    printf '%s\n' "$_r"
}

#[pub]
# Usage: str_distance build buidl -> 2
#
# Levenshtein distance: how many single-character edits turn one into the
# other. For suggesting what somebody meant, so a caller applies its own
# threshold; this only measures.
#
# One row rather than the full matrix, and the row lives in `$@` because POSIX
# has no arrays. `set --` replaces it each pass, which is the one data
# structure a POSIX shell has and is why this is the slowest thing here.
str_distance() {
    _a="$1"; _b="$2"
    _alen=${#_a}; _blen=${#_b}

    # Row zero: 0 1 2 ... blen
    set --
    _j=0
    while [ "$_j" -le "$_blen" ]; do set -- "$@" "$_j"; _j=$(( _j + 1 )); done

    _i=1
    while [ "$_i" -le "$_alen" ]; do
        _prev=$1
        _newrow="$_i"
        # The entry to the left is the one just computed, not the previous
        # row's. Read from `$@` it is the old row and every distance comes out
        # too large: kitten to sitting reported 6 where it is 3.
        _left=$_i
        _ac=$(printf '%s\n' "$_a" | cut -c "$_i")
        _j=1
        while [ "$_j" -le "$_blen" ]; do
            # `$@` is the previous row; field j+1 is its jth entry.
            eval "_cur=\${$(( _j + 1 ))}"
            _bc=$(printf '%s\n' "$_b" | cut -c "$_j")
            _cost=1
            [ "$_ac" = "$_bc" ] && _cost=0

            _best=$(( _cur + 1 ))
            _ins=$(( _left + 1 ))
            [ "$_ins" -lt "$_best" ] && _best=$_ins
            _sub=$(( _prev + _cost ))
            [ "$_sub" -lt "$_best" ] && _best=$_sub

            _newrow="$_newrow $_best"
            _prev=$_cur
            _left=$_best
            _j=$(( _j + 1 ))
        done
        # shellcheck disable=SC2086
        set -- $_newrow
        _i=$(( _i + 1 ))
    done

    eval "printf '%d' \"\${$(( _blen + 1 ))}\""
}
