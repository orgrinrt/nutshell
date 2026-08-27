#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/list-api - What the shipped list costs, floor against bash
# =============================================================================
#
# `benches/array-api` priced the techniques and picked one: keep the list as a
# string and let the shell field-split it. This prices what got built on top of
# that, both arms driving the shipped surface so the number carries the
# function boundary and the `eval` that a named list needs and a local variable
# does not.
#
# It also settles the question `benches/array-api` left open. A function's
# `set --` is local to that function, so nothing can split on the caller's
# behalf, and there are two ways out: `list_each`, which takes a function and
# calls it once per element, or `list_ref`, which hands back the raw string and
# leaves the caller to write `set -f`, `IFS` and the loop. The first is three
# lines shorter at every use and costs a function call per element. Whether
# that is affordable is what the second case below measures.
#
# **Both arms fork once to load their module**, because the two files define
# the same nine names and one shell cannot hold both. Identical on both sides,
# so it cancels. **Both run under bash**, so the technique is the variable and
# not the shell.
#
# Usage:
#   ./bench list-api [elements] [lookups]
# =============================================================================

use bench

ELEMS="${1:-400}"
LOOKUPS="${2:-200}"

ROOT="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
POSIXFILE="$ROOT/lib/list.sh"
BASHFILE="$ROOT/lib/list.bash.sh"

# Push, walk with `list_each`, index a sample, take a length. The elements
# include the three that break a naive split, so an arm that gets `IFS` or
# `set -f` wrong reports a different checksum and the run is refused.
read -r -d '' WORKLOAD <<'BODY' || true
    _SUM=0
    ck() { _SUM=$(( (_SUM * 31 + ${#1}) & 0x3fffffff )); }
    elem() {
        case "$1" in
            0) _E='an element with spaces' ;;
            1) _E='star * and ? here' ;;
            2) _E='one
two' ;;
            *) _E="element number $1" ;;
        esac
    }
    list_new a
    i=0
    while [ "$i" -lt "$ELEMS" ]; do elem "$i"; list_push a "$_E"; i=$(( i + 1 )); done
    list_each a ck
    i=0
    while [ "$i" -lt "$LOOKUPS" ]; do
        list_read v a "$(( i * ELEMS / LOOKUPS ))"; ck "$v"; i=$(( i + 1 ))
    done
    printf '%s|%s' "$_SUM" "$(list_len a)"
BODY

# The same, walked by the caller over `list_ref` instead of through
# `list_each`. Everything else is identical, so the gap is the function call
# per element and nothing else.
read -r -d '' DIRECT_WORKLOAD <<'BODY' || true
    _SUM=0
    ck() { _SUM=$(( (_SUM * 31 + ${#1}) & 0x3fffffff )); }
    elem() {
        case "$1" in
            0) _E='an element with spaces' ;;
            1) _E='star * and ? here' ;;
            2) _E='one
two' ;;
            *) _E="element number $1" ;;
        esac
    }
    list_new a
    i=0
    while [ "$i" -lt "$ELEMS" ]; do elem "$i"; list_push a "$_E"; i=$(( i + 1 )); done
    list_ref s a
    oldifs="$IFS"
    set -f; IFS="$LIST_SEP"
    for e in $s; do IFS="$oldifs"; set +f; ck "$e"; set -f; IFS="$LIST_SEP"; done
    IFS="$oldifs"; set +f
    i=0
    while [ "$i" -lt "$LOOKUPS" ]; do
        list_read v a "$(( i * ELEMS / LOOKUPS ))"; ck "$v"; i=$(( i + 1 ))
    done
    printf '%s|%s' "$_SUM" "$(list_len a)"
BODY

_run_against() {
    bash -c '
        nut_once() { return 0; }
        . "$1" || exit 1
        ELEMS="$2"; LOOKUPS="$3"
        eval "$4"
    ' _ "$1" "$ELEMS" "$LOOKUPS" "${2:-$WORKLOAD}"
}

arm_bash_list()    { _run_against "$BASHFILE"; }
arm_posix_list()   { _run_against "$POSIXFILE"; }
arm_bash_direct()  { _run_against "$BASHFILE"  "$DIRECT_WORKLOAD"; }
arm_posix_direct() { _run_against "$POSIXFILE" "$DIRECT_WORKLOAD"; }

_answer_of() { "$1"; }

bench_case "What the shipped list costs, floor against bash"
bench_size "$ELEMS"
bench_verify _answer_of

bench_arm "bash, one associative array"     arm_bash_list
bench_arm "posix floor, one per position"  arm_posix_list

bench_run || exit 1

bench_reset

bench_case "The same list, walked by the caller instead of through list_each"
bench_size "$ELEMS"
bench_verify _answer_of

bench_arm "bash, caller walks list_ref"     arm_bash_direct
bench_arm "posix floor, caller walks list_ref" arm_posix_direct

bench_run || exit 1

printf '\n'
printf 'Both arms fork once to load their module, and both run under bash.\n'
printf 'The two cases are two questions and only the gap inside each means\n'
printf 'anything. `benches/array-api` prices the techniques underneath.\n'
