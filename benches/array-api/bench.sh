#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/array-api - What an indexed array costs without declare -a
# =============================================================================
#
# `benches/maps` answered the associative half. This is the other half, and it
# is the larger one: counting every construct rather than the first error dash
# prints, indexed arrays appear in thirteen of the twenty files that cannot yet
# be read, against nine for associative arrays.
#
# **The workload is the shape the real uses have.** Reading them, the dominant
# pattern is append and then walk, with random access second and rarer:
# `_BENCH_LABEL+=("$1")` then `${_BENCH_LABEL[i]}`, `seen+=("$child")` then a
# membership test. So the arms append, walk the whole thing, index a sample,
# and take a length, in that proportion.
#
# **Elements hold arbitrary text**, which rules out the obvious answer before
# any measurement. `_BENCH_NOTE+=("${4:-}")` holds prose with spaces in it and
# a toml value can hold anything at all, so a space-delimited string is not a
# candidate and is not benched. The verify function below includes an element
# with spaces and an element with a newline, and an arm that mangles either
# answers differently and gets the whole run refused.
#
# Usage:
#   ./bench array-api [elements] [lookups]
# =============================================================================

use bench

ELEMS="${1:-400}"
LOOKUPS="${2:-200}"

# The input. Two of these are the reason a delimiter has to be chosen with care
# rather than assumed, and they sit at the front so every arm meets them.
#
# It leaves the element in `_E` rather than printing it. Printed and read back
# through a substitution it is a fork per element, and at four hundred elements
# that fork was the entire measurement: the first run of this bench had every
# arm within noise of bash and what it had measured was four hundred subshells
# with the array technique underneath too small to see. Every arm paid it
# equally, so no control could catch it, which is the reason it is written down
# here rather than quietly fixed.
_elem() {
    case "$1" in
        0) _E='an element with spaces in it' ;;
        1) _E='an element with
a newline in it' ;;
        *) _E="element number $1" ;;
    esac
}

# -----------------------------------------------------------------------------
# The arms. Each appends ELEMS elements, walks all of them accumulating a
# checksum, indexes LOOKUPS of them, and reports the length, so nothing can be
# optimised away by going unused and a mangled element shows up in the sum.
# -----------------------------------------------------------------------------

# A: bash indexed array. The thing being given up.
arm_bash_array() {
    local -a a=()
    local i sum=0 e
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; a+=("$_E"); done
    for e in "${a[@]}"; do sum=$(( sum + ${#e} )); done
    for (( i = 0; i < LOOKUPS; i++ )); do
        e="${a[$(( i * ELEMS / LOOKUPS ))]}"; sum=$(( sum + ${#e} ))
    done
    printf '%s|%s' "$sum" "${#a[@]}"
}

# B: one variable per slot, addressed by number through eval.
#
#    Random access without a scan, and no encoding anywhere because an index is
#    already a legal part of a name. `benches/maps` prices this shape at
#    roughly 1.3x for reads under the name `slots by index`; what it costs for
#    an append and a walk is what this arm is for.
arm_slots() {
    local i sum=0 e n=0
    for (( i = 0; i < ELEMS; i++ )); do
        _elem "$i"; eval "_ba_${i}=\"\$_E\""; n=$(( n + 1 ))
    done
    for (( i = 0; i < n; i++ )); do eval "e=\"\$_ba_${i}\""; sum=$(( sum + ${#e} )); done
    for (( i = 0; i < LOOKUPS; i++ )); do
        eval "e=\"\$_ba_$(( i * ELEMS / LOOKUPS ))\""; sum=$(( sum + ${#e} ))
    done
    printf '%s|%s' "$sum" "$n"
}

# C: one string, elements separated by a unit separator.
#
#    Appending is a concatenation and walking is one pass, which is the shape
#    the real uses have. Indexing is a scan, so this arm is expected to lose
#    exactly where the uses are rarest, and the question is by how much.
#
#    The separator is `\037` rather than a newline or a space because an
#    element holds arbitrary text and two of the elements here prove it.
arm_one_string() {
    local s="" i sum=0 e n=0 rest
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; s+="$_E"$'\037'; n=$(( n + 1 )); done
    rest="$s"
    while [[ -n "$rest" ]]; do
        e="${rest%%$'\037'*}"; rest="${rest#*$'\037'}"; sum=$(( sum + ${#e} ))
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        local want=$(( i * ELEMS / LOOKUPS )) j=0
        rest="$s"
        while (( j < want )); do rest="${rest#*$'\037'}"; j=$(( j + 1 )); done
        e="${rest%%$'\037'*}"; sum=$(( sum + ${#e} ))
    done
    printf '%s|%s' "$sum" "$n"
}

# D: the positional parameters.
#
#    The one list POSIX sh has natively, and the only arm here that needs no
#    eval and no scan. It costs the parameters themselves, so a function using
#    it cannot also read its own arguments, and there is exactly one per scope.
#    Whether that is affordable is a design question; what it costs is this.
arm_positional() {
    local i sum=0 e
    set --
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; set -- "$@" "$_E"; done
    for e in "$@"; do sum=$(( sum + ${#e} )); done
    for (( i = 0; i < LOOKUPS; i++ )); do
        eval "e=\"\${$(( i * ELEMS / LOOKUPS + 1 ))}\""; sum=$(( sum + ${#e} ))
    done
    printf '%s|%s' "$sum" "$#"
}

# -----------------------------------------------------------------------------
# The bench
# -----------------------------------------------------------------------------

# Every arm reports the same checksum and the same length. An arm that split on
# the wrong character loses or gains a byte on the two awkward elements and the
# harness refuses the run rather than reporting it as the fastest.
_answer_of() { "$1"; }

bench_case "What an indexed array costs without declare -a"
bench_size "$ELEMS"
bench_verify _answer_of

bench_arm "bash declare -a"          arm_bash_array
bench_arm "slots by index"           arm_slots
bench_arm "one string, unit-separated" arm_one_string  2000
bench_arm "positional parameters"    arm_positional

bench_run || exit 1

printf '\n'
printf 'Indexed arrays are in thirteen of the twenty files that cannot yet be\n'
printf 'read, against nine for associative arrays. This is the larger half.\n'
