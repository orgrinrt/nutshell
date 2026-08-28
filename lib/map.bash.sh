#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/map.bash.sh - A keyed table, over declare -A
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The same surface as `lib/map.sh`, over bash's own associative array. This is
# what bash 4 gets; the other is the floor, and the manifest picks between them
# above the sourcing.
#
# Nothing here encodes a key. The whole cost of the POSIX version is that a key
# has to become part of a variable name, and bash has a real table, so the key
# is the key.
#
# The two are held to the same answers by `tests/map_parity_test.sh`, which
# drives both over the same operations, the POSIX one under a real POSIX shell.
# Reading them side by side establishes nothing: one is a hash table and the
# other is a string of encoded names.
#
# Usage:
#   use map
#
#   map_new counts
#   map_set counts "lib/x.sh:1" hello
#   map_get counts "lib/x.sh:1"      -> hello
# =============================================================================

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE`
# and so needs bash. Under a POSIX shell it is not found, the
# `|| return 0` beside it fires on every load, and the module reports
# success having defined nothing.
[ -n "${_NUTSHELL_MAP_BASH_SH:-}" ] && return 0
_NUTSHELL_MAP_BASH_SH=1

# One table for every map, keyed by `<name>\037<key>`, rather than one
# `declare -A` per map created at run time.
#
# A per-map array needs `declare -gA "$name"` and then a nameref or an `eval`
# to reach it, and a nameref is bash 4.3. The unit separator cannot appear in a
# key that came from a path, and the alternative was inventing a delimiter that
# could.

# The same name check the floor makes, so both halves accept and refuse exactly
# the same names.
#
# Nothing here would execute a bad name: it lands in an array subscript rather
# than in an `eval`. It refuses anyway, because a name one half takes and the
# other rejects is a difference a caller discovers by switching shells, which
# is the one thing having two implementations must not cost.
_map_name_ok() {
    case "${1:-}" in
        "" | *[!A-Za-z0-9_]* ) return 1 ;;
        [0-9]* ) return 1 ;;
    esac
    return 0
}

declare -gA _NUT_MAP=()
declare -gA _NUT_MAP_ORDER=()

_map_k() { printf '%s\037%s' "$1" "$2"; }

#[pub]
# Start a map, or empty one that is already there.
# Usage: map_new counts
map_new() {
    _map_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" ]] || return 1
    map_clear "$1"
}

#[pub]
# Forget every key in a map.
# Usage: map_clear counts
map_clear() {
    _map_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" ]] || return 1
    local k
    for k in "${!_NUT_MAP[@]}"; do
        [[ "$k" == "${1}"$'\037'* ]] && unset '_NUT_MAP[$k]'
    done
    _NUT_MAP_ORDER["$1"]=""
}

#[pub]
# Put a value under a key.
# Usage: map_set counts "lib/x.sh:1" hello
map_set() {
    _map_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" && $# -ge 2 ]] || return 1
    local kk; kk="$(_map_k "$1" "$2")"
    # The order list only grows when the key is new, so setting twice does not
    # list it twice and `map_len` does not drift from what is there.
    [[ -v '_NUT_MAP[$kk]' ]] || _NUT_MAP_ORDER["$1"]="${_NUT_MAP_ORDER[$1]:-}"$'\037'"$2"
    _NUT_MAP["$kk"]="${3:-}"
}

#[pub]
# What is under a key, or nothing.
# Usage: map_get counts "lib/x.sh:1" -> hello
map_get() {
    _map_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" && $# -ge 2 ]] || return 1
    local kk; kk="$(_map_k "$1" "$2")"
    printf '%s' "${_NUT_MAP[$kk]:-}"
}

#[pub]
# What is under a key, into a variable of your naming.
#
# The bash counterpart of the floor's `map_read`. Reading through `map_get`
# costs the caller a fork; this one costs an assignment.
#
# Usage: map_read v counts "lib/x.sh:1"; printf '%s' "$v"
map_read() {
    _map_name_ok "${1:-}" && _map_name_ok "${2:-}" || return 1
    [[ $# -ge 3 ]] || return 1
    printf -v "$1" '%s' "${_NUT_MAP["$2"$'\037'"$3"]:-}"
}

#[pub]
# Is the key there at all. Distinct from an empty value.
# Usage: map_has counts "lib/x.sh:1" -> returns 0 when set
map_has() {
    _map_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" && $# -ge 2 ]] || return 1
    local kk; kk="$(_map_k "$1" "$2")"
    [[ -v '_NUT_MAP[$kk]' ]]
}

#[pub]
# Forget one key.
# Usage: map_del counts "lib/x.sh:1"
map_del() {
    _map_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" && $# -ge 2 ]] || return 1
    local kk; kk="$(_map_k "$1" "$2")"
    [[ -v '_NUT_MAP[$kk]' ]] || return 0
    unset '_NUT_MAP[$kk]'
    # `|| [[ -n "$k" ]]`, because the last field has no newline after it and
    # `read` returns non-zero having set it. Without that the most recently
    # added key is dropped from the order on every delete, which is the same
    # defect `_lib_nut_lookup` carries a note about.
    local out="" k
    while IFS= read -r k || [[ -n "$k" ]]; do
        [[ -z "$k" || "$k" == "$2" ]] && continue
        out+=$'\037'"$k"
    done < <(printf '%s' "${_NUT_MAP_ORDER[$1]:-}" | tr $'\037' '\n')
    _NUT_MAP_ORDER["$1"]="$out"
}

#[pub]
# How many keys are set.
# Usage: map_len counts -> 3
map_len() {
    _map_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" ]] || return 1
    local n=0 k
    for k in "${!_NUT_MAP[@]}"; do
        [[ "$k" == "${1}"$'\037'* ]] && n=$(( n + 1 ))
    done
    printf '%s' "$n"
}

#[pub]
# Every key, one per line, in the order they were first set.
# Usage: map_keys counts
map_keys() {
    _map_name_ok "${1:-}" || return 1
    [[ -n "${1:-}" ]] || return 1
    # `|| [[ -n "$k" ]]` for the last field, which has no newline after it.
    local k
    while IFS= read -r k || [[ -n "$k" ]]; do
        [[ -n "$k" ]] && printf '%s\n' "$k"
    done < <(printf '%s' "${_NUT_MAP_ORDER[$1]:-}" | tr $'\037' '\n')
}
