#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/list.sh - An ordered list, without declare -a
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The POSIX floor. Reads under any POSIX sh; `lib/list.bash.sh` is the same
# surface for bash and is picked by a `#[shell(bash4)]` gate in `lib.nut`.
#
# The list is one variable per position, and the string form with a unit
# separator between elements is built on demand for a caller that wants to walk
# it itself.
#
# That is the opposite way round from what `benches/array-api` concluded, and
# the reason is worth stating because it is the one thing that bench could not
# see. It measured a list held in a local variable, where appending is `s+=`
# and bash extends the string in place. A list with a name cannot use `+=`: the
# assignment goes through `eval`, which rebuilds the whole string on every
# push, so appending becomes quadratic. `benches/list-api` caught it as 165% of
# bash at four hundred elements and 468% at two thousand, on the same code.
#
# Slots have no such problem. A push is one assignment, an index is one lookup,
# and the length is a counter, all regardless of how long the list is. What
# they cost instead is the walk, which is one `eval` per element rather than
# one field split for the whole list, and `list_each` pays that.
#
# So the string is the interchange form rather than the storage form. Where a
# caller walks it via `list_ref`, the two lines that make that correct are the
# caller's, which is what `LIST_SEP` is exported for:
#
#   `set -f`, because field splitting is followed by pathname expansion, and an
#   element holding `*` would otherwise become a directory listing.
#
#   `IFS` set to the separator alone, or every space and newline inside an
#   element splits it further.
#
# Usage:
#   use list
#
#   list_new args
#   list_push args "--flag"
#   list_push args "a value with spaces"
#   list_len args                      # 2
#   list_get args 1                    # a value with spaces
#   list_read v args 1                 # leaves it in $v, no subshell
#   list_each args printf              # calls printf once per element
# =============================================================================

nut_once || return 0

# The separator. A unit separator, which is what it is for, and it is exported
# because a caller walking `list_str` itself has to set `IFS` to it.
LIST_SEP=$(printf '\037')
export LIST_SEP

#[pub]
# Start an empty list, or empty an existing one.
# Usage: list_new args
list_new() {
    [ -n "${1:-}" ] || return 1
    eval "_lidx_${1}=0"
}

#[pub]
# Add one element to the end.
#
# One assignment, whatever the length. Refuses a value containing the separator
# rather than letting it through, because `list_str` and `list_ref` hand back a
# string with that separator in it and an element carrying one would split into
# two on the way out. Checked rather than documented and hoped for; the
# alternative is escaping, which costs a pass over every element in both
# directions to carry a character none of nutshell's own lists has held.
#
# Usage: list_push args "a value"
list_push() {
    [ -n "${1:-}" ] && [ $# -ge 2 ] || return 1
    case "$2" in
        *"$LIST_SEP"*) return 2 ;;
    esac
    eval "_lp_n=\${_lidx_${1}:-0}"
    eval "_lst_${1}_${_lp_n}=\$2"
    eval "_lidx_${1}=$(( _lp_n + 1 ))"
}

#[pub]
# How many elements are in it.
# Usage: list_len args -> 2
list_len() {
    [ -n "${1:-}" ] || return 1
    eval "printf '%s' \"\${_lidx_$1:-0}\""
}

#[pub]
# The element at an index, counting from zero, or nothing.
# Usage: list_get args 1 -> a value with spaces
list_get() {
    [ -n "${1:-}" ] && [ $# -ge 2 ] || return 1
    list_read _lg_v "$1" "$2" || return 1
    printf '%s' "$_lg_v"
}

#[pub]
# The element at an index, into a variable of your naming.
#
# `list_get` prints, so reading one element costs the caller a fork.
# `benches/maps` measured a fork per operation as costing more than the whole
# substitution technique does, which is why this exists beside it.
#
# Usage: list_read v args 1; printf '%s' "$v"
list_read() {
    [ -n "${1:-}" ] && [ -n "${2:-}" ] && [ $# -ge 3 ] || return 1
    eval "_lr_n=\${_lidx_${2}:-0}"
    [ "$3" -ge 0 ] && [ "$3" -lt "$_lr_n" ] || { eval "$1=''"; return 1; }
    eval "$1=\"\$_lst_${2}_${3}\""
}

#[pub]
# The raw string, separator and all.
#
# Built on demand, since the storage is one variable per position. For a caller
# that wants to walk the list without a function call per element:
#
#   oldifs="$IFS"; set -f; IFS="$LIST_SEP"
#   for e in $(list_str args); do ...; done
#   IFS="$oldifs"; set +f
#
# `list_ref` is the same string without the fork this one costs.
#
# Usage: list_str args
list_str() {
    [ -n "${1:-}" ] || return 1
    list_ref _ls_v "$1" || return 1
    printf '%s' "$_ls_v"
}

#[pub]
# The raw string, into a variable of your naming.
#
# Usage: list_ref s args
list_ref() {
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
    eval "_lf_n=\${_lidx_${2}:-0}"
    _lf_out=""; _lf_i=0
    while [ "$_lf_i" -lt "$_lf_n" ]; do
        eval "_lf_e=\"\$_lst_${2}_${_lf_i}\""
        _lf_out="${_lf_out}${_lf_e}${LIST_SEP}"
        _lf_i=$(( _lf_i + 1 ))
    done
    eval "$1=\"\$_lf_out\""
}

#[pub]
# Call a function once per element, in order.
#
# Walks the slots directly, so no string is built and the positional parameters
# are untouched. A caller's own arguments survive it.
#
# Usage: list_each args printf
list_each() {
    [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
    eval "_le_n=\${_lidx_${1}:-0}"
    _le_fn="$2"; _le_i=0
    while [ "$_le_i" -lt "$_le_n" ]; do
        eval "_le_e=\"\$_lst_${1}_${_le_i}\""
        "$_le_fn" "$_le_e" || { _le_rc=$?; return "$_le_rc"; }
        _le_i=$(( _le_i + 1 ))
    done
}
