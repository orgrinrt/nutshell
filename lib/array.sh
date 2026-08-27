#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/array.sh - Operations over a list of arguments
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0. Everything here works on `"$@"`, so it needs no container and reads
# under any POSIX sh.
#
# The three functions that used to rewrite a bash array in place through a
# nameref take a `list` name now. A nameref is bash 4.3, an array is bash at
# all, and neither reads on the floor. Operating on the container the library
# ships means one implementation serves both halves of it.
#
# Usage:
#   use array
#
#   arr_contains "b" a b c        # returns 0
#   arr_index    "b" a b c        # 1
#   arr_filter   "a*" apple bat   # apple
#
#   list_new l; list_push l b; list_push l a; list_push l b
#   arr_unique l                  # l is now b, a
# =============================================================================

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot depend on a bash-only function to
# decide whether it has been loaded: under a POSIX shell `nut_once` is not
# found, the `|| return 0` returns from the whole file, and the module then
# defines nothing while reporting success. That is worse than failing, because
# the caller has no way to tell.
[ -n "${_NUTSHELL_ARRAY_SH:-}" ] && return 0
_NUTSHELL_ARRAY_SH=1

# `list` is required and is not resolved from here.
#
# The fallback that stood here reached for `BASH_SOURCE` inside the branch that
# only runs when the shell is not bash, and in dash that is a fatal expansion
# error rather than a fallback: sourcing this file aborted the caller with
# status 2 and no message, which is worse than the silent no-op it replaced,
# in exactly the shell it was written for. `dash -n` does not catch it, because
# it is a runtime expansion rather than a parse error.
#
# There is no fix, only a different design: POSIX gives a sourced file no way to
# find its own path, and `$0` is the caller. So this refuses instead. `map.sh`
# and `list.sh` both demonstrate that a floor file is cleanest with nothing to
# resolve, and this one has a real dependency, so it says so.
if command -v use >/dev/null 2>&1; then
    use list
elif ! command -v list_new >/dev/null 2>&1; then
    printf 'array: needs `list`. Source lib/list.sh before this file, or use\n' >&2
    printf '  nutshell, which resolves it.\n' >&2
    return 1
fi

# -----------------------------------------------------------------------------
# Over the arguments
# -----------------------------------------------------------------------------

#[pub]
# Whether the list of arguments holds an element.
# Usage: arr_contains "needle" "$@" -> returns 0 when present
arr_contains() {
    _ac_needle="${1:-}"
    shift || return 1
    for _ac_item in "$@"; do
        [ "$_ac_item" = "$_ac_needle" ] && return 0
    done
    return 1
}

#[pub]
# Where an element sits, counting from zero, or 255 and a non-zero status.
# Usage: arr_index "needle" "$@" -> prints the index or 255
arr_index() {
    _ai_needle="${1:-}"
    shift || return 1
    _ai_i=0
    for _ai_item in "$@"; do
        [ "$_ai_item" = "$_ai_needle" ] && { printf '%s\n' "$_ai_i"; return 0; }
        _ai_i=$(( _ai_i + 1 ))
    done
    printf '255\n'
    return 1
}

#[pub]
#[allow(trivial_wrapper)]
# How many arguments there are.
# Usage: arr_length "$@" -> prints the count
arr_length() {
    printf '%s\n' "$#"
}

#[pub]
#[allow(trivial_wrapper)]
# Whether there are none.
# Usage: arr_is_empty "$@" -> returns 0 when empty
arr_is_empty() {
    [ $# -eq 0 ]
}

#[pub]
#[allow(trivial_wrapper)]
# The first argument.
# Usage: arr_first "$@" -> prints it
arr_first() {
    [ $# -gt 0 ] && printf '%s\n' "$1"
}

#[pub]
# The last argument.
#
# Walked to rather than reached with `${!#}`, which is bash's indirect
# expansion. A loop that keeps the value it last saw is the POSIX way and is
# not slower for any list a shell would hold.
#
# Usage: arr_last "$@" -> prints it
arr_last() {
    [ $# -gt 0 ] || return 1
    for _al_item in "$@"; do :; done
    printf '%s\n' "$_al_item"
}

#[pub]
# The arguments matching a glob, one per line.
# Usage: arr_filter "a*" apple bat -> apple
arr_filter() {
    _af_pattern="${1:-}"
    shift || return 1
    for _af_item in "$@"; do
        # Unquoted on the right so it is a pattern rather than a literal, which
        # is the whole point of the function.
        # shellcheck disable=SC2254
        case "$_af_item" in
            $_af_pattern) printf '%s\n' "$_af_item" ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Over a list, rewritten in place
# -----------------------------------------------------------------------------

# The check that a caller passed a list, and not something else.
#
# These three used to take a bash array through a nameref. That call shape now
# names a list that does not exist, and without this they would treat it as an
# empty list, report success, and leave the array untouched, which is the worst
# outcome for a consumer upgrading: silent, and rc 0.
#
# `list_exists` rather than reaching for either half's storage directly: the
# two keep their counter in different places, and reaching for one makes this
# work under one shell and refuse every real list under the other.
_arr_is_list() {
    [ -n "${1:-}" ] || return 1
    list_exists "$1"
}

#[pub]
# Drop repeats, keeping the first of each and the order of what is left.
# Usage: arr_unique l
arr_unique() {
    _arr_is_list "${1:-}" || return 1
    _au_n="$(list_len "$1")"
    [ "$_au_n" -le 1 ] && return 0
    _au_seen=""
    _au_keep=""
    _au_i=0
    while [ "$_au_i" -lt "$_au_n" ]; do
        list_read _au_e "$1" "$_au_i"
        # The seen-set is a string, so every element in it is fenced by a
        # separator on both sides. `ab` then does not match inside `cab`, and a
        # value equal to another's suffix stays its own element. The list
        # refuses an element holding the separator, so the fencing is
        # unambiguous.
        #
        # One separator is prefixed at the check and one appended at the store,
        # rather than one at each end of both. Fencing both sides of an empty
        # seen-set produces two adjacent separators, which is exactly the
        # pattern an empty element searches for, so the first empty element
        # ever seen was reported as a repeat and dropped.
        case "${LIST_SEP}${_au_seen}" in
            *"${LIST_SEP}${_au_e}${LIST_SEP}"*) : ;;
            *)
                _au_seen="${_au_seen}${_au_e}${LIST_SEP}"
                _au_keep="${_au_keep}${_au_e}${LIST_SEP}"
                ;;
        esac
        _au_i=$(( _au_i + 1 ))
    done
    _arr_refill "$1" "$_au_keep"
}

#[pub]
# Reverse it.
# Usage: arr_reverse l
arr_reverse() {
    _arr_is_list "${1:-}" || return 1
    _ar_n="$(list_len "$1")"
    [ "$_ar_n" -le 1 ] && return 0
    _ar_keep=""
    _ar_i=$(( _ar_n - 1 ))
    while [ "$_ar_i" -ge 0 ]; do
        list_read _ar_e "$1" "$_ar_i"
        _ar_keep="${_ar_keep}${_ar_e}${LIST_SEP}"
        _ar_i=$(( _ar_i - 1 ))
    done
    _arr_refill "$1" "$_ar_keep"
}

#[pub]
# Sort it, the way `sort` does.
#
# Through a file rather than a pipe, because a pipe puts the read in a subshell
# and the list it writes there does not survive. An element holding a newline
# cannot go through `sort` at all and is refused rather than silently split
# into two, since a sort that loses an element is worse than one that says it
# cannot.
#
# Usage: arr_sort l
arr_sort() {
    _arr_is_list "${1:-}" || return 1
    _as_n="$(list_len "$1")"
    [ "$_as_n" -le 1 ] && return 0

    # A literal newline, because `$(printf '\n')` is the empty string: command
    # substitution strips trailing newlines, so the pattern became `*""*`, which
    # matches everything, and the guard refused every list including the ones it
    # should have sorted. It returned 2 and the caller saw its list unchanged.
    _as_nl='
'
    _as_i=0
    while [ "$_as_i" -lt "$_as_n" ]; do
        list_read _as_e "$1" "$_as_i"
        case "$_as_e" in
            *"$_as_nl"*) return 2 ;;
        esac
        _as_i=$(( _as_i + 1 ))
    done

    _as_f="$(mktemp "${TMPDIR:-/tmp}/nut-sort.XXXXXX")" || return 1
    _as_i=0
    while [ "$_as_i" -lt "$_as_n" ]; do
        list_read _as_e "$1" "$_as_i"
        printf '%s\n' "$_as_e"
        _as_i=$(( _as_i + 1 ))
    done | sort > "$_as_f"

    list_new "$1"
    while IFS= read -r _as_e || [ -n "$_as_e" ]; do
        list_push "$1" "$_as_e"
    done < "$_as_f"
    rm -f "$_as_f"
}

# Empty a list and fill it from a separated string.
#
# The answer is built in a local string rather than in a second list. A scratch
# list needed a name, and any name it could have was one a caller might hold:
# a hardcoded one ate a list called that, and one derived from the caller's ate
# a list called the derivation. Closing that properly meant reserving the
# scratch space in `list.sh`, at which point `array.sh` could not use it either,
# which is the honest signal that the scratch should not have existed.
#
# The list refuses an element holding the separator, so splitting on it here
# cannot break an element apart.
_arr_refill() {
    _ao_name="$1"; _ao_str="$2"
    list_new "$_ao_name"
    [ -n "$_ao_str" ] || return 0
    _ao_ifs="$IFS"
    set -f; IFS="$LIST_SEP"
    # shellcheck disable=SC2086
    set -- $_ao_str
    IFS="$_ao_ifs"; set +f
    for _ao_e in "$@"; do
        list_push "$_ao_name" "$_ao_e"
    done
}
