#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/map-api - What the shipped map costs, floor against bash
# =============================================================================
#
# `benches/maps` priced the techniques: a bare `declare -A` against a bare
# `eval` on an encoded name, with no function boundary and nothing tracking
# insertion order. It answered which technique to build on and said nothing
# about what got built.
#
# This prices what got built. Both arms drive the shipped surface, `map_new`
# through `map_keys`, over the same operations, and the difference between them
# is what a caller pays for the floor: a function call per operation either way,
# an encoding pass per key on one side, a hash lookup on the other, and an order
# string that both maintain because `map_keys` promises insertion order.
#
# **Both arms fork a subshell to load their module**, because the two files
# define the same eight names and one shell cannot hold both. That fork is
# identical on both sides and cancels out of the comparison. It does mean these
# numbers do not compare to `benches/maps`, which forks nothing, and they are
# not put next to those.
#
# **Both run under bash**, including the floor. That is deliberate: the question
# is what the technique costs, and running one arm under `dash` would answer a
# different question with the shell as the variable. What the floor costs under
# a real POSIX shell is worth measuring and is not this.
#
# The keys are nutshell's own shape, `<path>:<n>`, because that shape is what
# forced an encoding at all.
#
# Usage:
#   ./bench map-api [entries] [lookups]
# =============================================================================

use bench

ENTRIES="${1:-400}"
LOOKUPS="${2:-200}"

ROOT="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"
POSIXFILE="$ROOT/lib/map.sh"
BASHFILE="$ROOT/lib/map.bash.sh"

# The workload, written once and run against whichever module was loaded.
#
# Every operation the surface has, in a shape a caller would actually write:
# fill, read back, miss, ask what is present, take the length, walk the keys,
# delete a slice, walk them again. An arm that only set and got would price the
# two cheapest operations and call it the API.
read -r -d '' WORKLOAD <<'BODY' || true
    map_new m
    i=0
    while [ "$i" -lt "$ENTRIES" ]; do
        map_set m "lib/some-module.sh:$i" "value number $i"
        i=$(( i + 1 ))
    done
    last=""
    i=0
    while [ "$i" -lt "$LOOKUPS" ]; do
        last="$(map_get m "lib/some-module.sh:$(( i * ENTRIES / LOOKUPS ))")"
        i=$(( i + 1 ))
    done
    i=0
    while [ "$i" -lt "$LOOKUPS" ]; do
        map_get m "no/such-key.sh:$i" >/dev/null 2>&1 || last="MISS"
        i=$(( i + 1 ))
    done
    i=0
    while [ "$i" -lt "$LOOKUPS" ]; do
        map_has m "lib/some-module.sh:$i" && last="present"
        i=$(( i + 1 ))
    done
    len="$(map_len m)"
    keys="$(map_keys m | wc -l)"
    i=0
    while [ "$i" -lt "$LOOKUPS" ]; do
        map_del m "lib/some-module.sh:$i"
        i=$(( i + 1 ))
    done
    printf '%s|%s|%s|%s' "$last" "$len" "$keys" "$(map_len m)"
BODY

# The same workload with the one line that reads a value changed to the
# out-variable form. Everything else is identical, so the gap between a
# `$(map_get ...)` arm and its `map_read` twin is the caller's fork and nothing
# else.
READ_WORKLOAD="${WORKLOAD/last=\"\$(map_get m \"lib\/some-module.sh:\$(( i * ENTRIES \/ LOOKUPS ))\")\"/map_read last m \"lib\/some-module.sh:\$(( i * ENTRIES \/ LOOKUPS ))\"}"

# A read-dominated workload, which is the shape nutshell's own tables have: a
# config cache or an attribute table is filled once and then read from on every
# lookup for the rest of the run. The workload above is a fifth reads, so it
# prices a fill more than a use, and the two answer different questions.
#
# Ten reads per entry, no deletes, and the reads go through the out-variable
# form because the point here is what the table costs in use.
read -r -d '' HOT_WORKLOAD <<'BODY' || true
    map_new m
    i=0
    while [ "$i" -lt "$ENTRIES" ]; do
        map_set m "lib/some-module.sh:$i" "value number $i"
        i=$(( i + 1 ))
    done
    last=""; r=0
    while [ "$r" -lt 10 ]; do
        i=0
        while [ "$i" -lt "$ENTRIES" ]; do
            map_read last m "lib/some-module.sh:$i"
            i=$(( i + 1 ))
        done
        r=$(( r + 1 ))
    done
    printf '%s|%s' "$last" "$(map_len m)"
BODY

# -----------------------------------------------------------------------------
# The arms
# -----------------------------------------------------------------------------

_run_against() {
    bash -c '
        nut_once() { return 0; }
        . "$1" || exit 1
        ENTRIES="$2"; LOOKUPS="$3"
        eval "$4"
    ' _ "$1" "$ENTRIES" "$LOOKUPS" "${2:-$WORKLOAD}"
}

# A: the bash module, one associative array keyed by name and key.
arm_bash_map() { _run_against "$BASHFILE"; }

# B: the POSIX floor, one shell variable per entry, key encoded into the name.
arm_posix_map() { _run_against "$POSIXFILE"; }

# C and D: the same two, reading through `map_read` rather than through a
#          command substitution on `map_get`.
arm_bash_read()  { _run_against "$BASHFILE"  "$READ_WORKLOAD"; }
arm_posix_read() { _run_against "$POSIXFILE" "$READ_WORKLOAD"; }

# E and F: the read-dominated shape, which is what a cache actually does.
#          These two answer separately from the four above and are not a
#          continuation of them: a different workload is a different question,
#          and only the gap between this pair means anything.
arm_bash_hot()  { _run_against "$BASHFILE"  "$HOT_WORKLOAD"; }
arm_posix_hot() { _run_against "$POSIXFILE" "$HOT_WORKLOAD"; }

# -----------------------------------------------------------------------------
# The bench
# -----------------------------------------------------------------------------

# Both arms print the same four numbers, so an encoding that collided two keys,
# or an order string that dropped its last field, shows up as a disagreement
# and the harness refuses the run rather than reporting a winner. The last of
# the four is the length after deleting a slice, which is the field that caught
# the dropped-field defect in the bash arm's own order string.
_answer_of() { "$1"; }

bench_case "What the shipped map costs, floor against bash"
bench_size "$ENTRIES"
bench_verify _answer_of

bench_arm "bash, one associative array"  arm_bash_map
bench_arm "posix floor, encoded names"   arm_posix_map
bench_arm "bash, read into a variable"   arm_bash_read
bench_arm "posix floor, read into a variable" arm_posix_read

bench_run || exit 1

# A second case rather than two more arms, because the read-heavy workload
# answers a different string and the agreement control is right to refuse it as
# one comparison. It is a different question and it gets its own table.
bench_reset

bench_case "The same map under a read-heavy load"
bench_size "$ENTRIES"
bench_verify _answer_of
bench_arm "bash, read-heavy"        arm_bash_hot
bench_arm "posix floor, read-heavy" arm_posix_hot

bench_run || exit 1

printf '\n'
printf 'Both arms fork once to load their module, and both run under bash.\n'
printf 'Neither number compares to benches/maps, which forks nothing.\n'
