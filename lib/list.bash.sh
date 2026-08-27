#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/list.bash.sh - An ordered list, on bash's own arrays
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The bash half of `lib/list.sh`, same surface, picked by a `#[shell(bash4)]`
# gate in `lib.nut`. Where the floor keeps one string and lets the shell split
# it, this keeps one associative array with the index in the key, so a push and
# an index are both a single lookup.
#
# `benches/list-api` prices the two against each other. `benches/array-api`
# prices the techniques underneath them, and the floor's is 117% of bash's own
# `declare -a` when indexing and inside the noise when only walking.
#
# The surface is `lib/list.sh`. `tests/list_parity_test.sh` drives both under
# their own shells and compares the answers, which is the only thing that says
# they agree: one is a hash table and the other is a string, and reading them
# side by side establishes nothing.
# =============================================================================

nut_once || return 0

# The same separator the floor uses, so a caller reaching for `list_str` gets
# the same string from either half and does not have to ask which is loaded.
LIST_SEP=$'\037'
export LIST_SEP


# The same name check the floor makes, so both halves accept and refuse exactly
# the same names.
#
# Nothing here would execute a bad name: it lands in an array subscript rather
# than in an `eval`. It refuses anyway, because a name one half takes and the
# other rejects is a difference a caller discovers by switching shells, which
# is the one thing having two implementations must not cost.
_list_name_ok() {
    case "${1:-}" in
        "" | *[!A-Za-z0-9_]* ) return 1 ;;
        [0-9]* ) return 1 ;;
    esac
    return 0
}

declare -gA _NUT_LIST=()
declare -gA _NUT_LIST_N=()

#[pub]
# Start an empty list, or empty an existing one.
# Usage: list_new args
list_new() {
    _list_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" ]] || return 1
    local k n="${_NUT_LIST_N[$1]:-0}" i
    for (( i = 0; i < n; i++ )); do unset '_NUT_LIST[$1'$'\037'"$i]"; done
    _NUT_LIST_N[$1]=0
}

#[pub]
# Whether a list has been started, as distinct from being empty.
#
# `list_len` answers zero for both, so nothing could tell a list that exists
# and holds nothing from a name that is not a list at all. `array.sh` needs
# that difference: its three rewrites used to take a bash array through a
# nameref, and without this check that old call shape names a list that does
# not exist, gets treated as an empty one, and the function reports success
# having done nothing.
#
# Usage: list_exists args -> returns 0 when started
list_exists() {
    _list_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" ]] || return 1
    [[ -n "${_NUT_LIST_N[$1]+set}" ]]
}

#[pub]
# Add one element to the end.
#
# Refuses a value containing the separator, the same as the floor does. Nothing
# here would mangle on it, since the index is in the key rather than in the
# text, and it refuses anyway: a value that one half takes and the other
# rejects is worse than a limit both hold to.
#
# Usage: list_push args "a value"
list_push() {
    _list_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" && $# -ge 2 ]] || return 1
    [[ "$2" == *"$LIST_SEP"* ]] && return 2
    local n="${_NUT_LIST_N[$1]:-0}"
    _NUT_LIST["$1$LIST_SEP$n"]="$2"
    _NUT_LIST_N[$1]=$(( n + 1 ))
}

#[pub]
# The raw string, separator and all.
# Usage: list_str args
list_str() {
    _list_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" ]] || return 1
    local n="${_NUT_LIST_N[$1]:-0}" i out=""
    for (( i = 0; i < n; i++ )); do out+="${_NUT_LIST["$1$LIST_SEP$i"]}$LIST_SEP"; done
    printf '%s' "$out"
}

#[pub]
# The raw string, into a variable of your naming.
#
# `list_str` prints, so walking through it costs a fork. This is the same
# string without one.
#
# Usage: list_ref s args
list_ref() {
    _list_name_ok "${1:-}" && _list_name_ok "${2:-}" || return 1
    local n="${_NUT_LIST_N[$2]:-0}" i out=""
    for (( i = 0; i < n; i++ )); do out+="${_NUT_LIST["$2$LIST_SEP$i"]}$LIST_SEP"; done
    printf -v "$1" '%s' "$out"
}

#[pub]
# How many elements are in it.
# Usage: list_len args -> 2
list_len() {
    _list_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" ]] || return 1
    printf '%s' "${_NUT_LIST_N[$1]:-0}"
}

#[pub]
# The element at an index, counting from zero, or nothing.
# Usage: list_get args 1 -> a value with spaces
list_get() {
    _list_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" && $# -ge 2 ]] || return 1
    local v; list_read v "$1" "$2" || return 1
    printf '%s' "$v"
}

#[pub]
# The element at an index, into a variable of your naming.
# Usage: list_read v args 1; printf '%s' "$v"
list_read() {
    _list_name_ok "${1:-}" && _list_name_ok "${2:-}" || return 1
    [[ $# -ge 3 ]] || return 1
    # A non-numeric index is refused on both halves rather than one erroring
    # and the other quietly treating it as zero. Arithmetic context turns `abc`
    # into 0 under bash and into a fatal error under dash, which is a parity
    # divergence in the one place a caller is most likely to pass something it
    # did not check.
    case "${3:-}" in
        '' | *[!0-9-]* | -*-* ) printf -v "$1" '%s' ""; return 1 ;;
    esac
    local n="${_NUT_LIST_N[$2]:-0}"
    if [[ "$3" -lt 0 || "$3" -ge "$n" ]]; then printf -v "$1" '%s' ""; return 1; fi
    printf -v "$1" '%s' "${_NUT_LIST["$2$LIST_SEP$3"]}"
}

#[pub]
# Call a function once per element, in order.
# Usage: list_each args printf
list_each() {
    _list_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" && -n "${2:-}" ]] || return 1
    local n="${_NUT_LIST_N[$1]:-0}" i rc
    for (( i = 0; i < n; i++ )); do
        "$2" "${_NUT_LIST["$1$LIST_SEP$i"]}" || { rc=$?; return "$rc"; }
    done
}
