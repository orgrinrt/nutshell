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
#
# The checksum is a rolling one rather than a total, because a total is
# order-blind: an arm that stores the list backwards and never notices reports
# the same sum of lengths as one that gets it right. `sum * 31 + len` does not,
# which matters here because one arm below builds the list by prepending and
# has to undo that to be correct.
# -----------------------------------------------------------------------------

CHUNK=64   # elements per rope chunk

_ck() { _SUM=$(( (_SUM * 31 + ${#1}) & 0x3fffffff )); }

# A: bash indexed array. The thing being given up.
arm_bash_array() {
    local -a a=()
    local i e; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; a+=("$_E"); done
    for e in "${a[@]}"; do _ck "$e"; done
    for (( i = 0; i < LOOKUPS; i++ )); do _ck "${a[$(( i * ELEMS / LOOKUPS ))]}"; done
    printf '%s|%s' "$_SUM" "${#a[@]}"
}

# A2: the same, assigning by index rather than appending. Whether bash's `+=`
#     is its own fast path or the same operation spelled shorter.
arm_bash_by_index() {
    local -a a=()
    local i e; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; a[i]="$_E"; done
    for e in "${a[@]}"; do _ck "$e"; done
    for (( i = 0; i < LOOKUPS; i++ )); do _ck "${a[$(( i * ELEMS / LOOKUPS ))]}"; done
    printf '%s|%s' "$_SUM" "${#a[@]}"
}

# B: one variable per slot, addressed by number through eval.
#
#    Random access without a scan, and no encoding anywhere because an index is
#    already a legal part of a name. `benches/maps` prices this shape at
#    roughly 1.3x for reads under the name `slots by index`; what it costs for
#    an append and a walk is what this arm is for.
arm_slots() {
    local i e n=0; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do
        _elem "$i"; eval "_ba_${i}=\"\$_E\""; n=$(( n + 1 ))
    done
    for (( i = 0; i < n; i++ )); do eval "e=\"\$_ba_${i}\""; _ck "$e"; done
    for (( i = 0; i < LOOKUPS; i++ )); do
        eval "e=\"\$_ba_$(( i * ELEMS / LOOKUPS ))\""; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$n"
}

# B2: the same slots, with the appends batched into one `eval` per block.
#
#     If `eval` itself is the cost rather than the assignment, batching is the
#     lever, and this says by how much. The value has to be baked into the
#     program text, which means quoting it, and the quoting here uses bash's
#     `//` substitution: **this arm is bash-only and is a diagnostic, not a
#     candidate.** POSIX sh has no bulk substitution and escaping a value
#     character by character would cost more than the `eval` it saves.
arm_slots_batched() {
    local i e n=0 prog="" q; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do
        _elem "$i"
        q="${_E//\'/\'\\\'\'}"
        prog="${prog}_bb_${i}='${q}';"
        n=$(( n + 1 ))
        if (( n % CHUNK == 0 )); then eval "$prog"; prog=""; fi
    done
    [[ -n "$prog" ]] && eval "$prog"
    for (( i = 0; i < n; i++ )); do eval "e=\"\$_bb_${i}\""; _ck "$e"; done
    for (( i = 0; i < LOOKUPS; i++ )); do
        eval "e=\"\$_bb_$(( i * ELEMS / LOOKUPS ))\""; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$n"
}

# B3: the same list, with one extra `eval` per append.
#
#     The gap between this and B is one `eval` per element and nothing else, so
#     it prices the call itself rather than the assignment through it. That is
#     the number B2 needs to be read against: if batching wins by roughly this
#     much, `eval` is the cost; if it wins by more or less, something else is.
#
#     It builds the same list and answers the same string, so it competes
#     honestly rather than sitting outside the comparison.
arm_slots_double_eval() {
    local i e n=0; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do
        _elem "$i"; eval "_bd_${i}=\"\$_E\""; eval ":"; n=$(( n + 1 ))
    done
    for (( i = 0; i < n; i++ )); do eval "e=\"\$_bd_${i}\""; _ck "$e"; done
    for (( i = 0; i < LOOKUPS; i++ )); do
        eval "e=\"\$_bd_$(( i * ELEMS / LOOKUPS ))\""; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$n"
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
    local s="" i e n=0 rest; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; s+="$_E"$'\037'; n=$(( n + 1 )); done
    rest="$s"
    while [[ -n "$rest" ]]; do
        e="${rest%%$'\037'*}"; rest="${rest#*$'\037'}"; _ck "$e"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        local want=$(( i * ELEMS / LOOKUPS )) j=0
        rest="$s"
        while (( j < want )); do rest="${rest#*$'\037'}"; j=$(( j + 1 )); done
        e="${rest%%$'\037'*}"; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$n"
}

# C2: a rope. Several strings, each holding at most CHUNK elements, with the
#     chunks themselves in slots.
#
#     Appending is a concatenation onto the last chunk and walking is one pass
#     per chunk, so both keep what the single string had. Indexing divides to
#     find the chunk and then scans inside it, so the scan is bounded by the
#     chunk size instead of by the length of the list. That is the one thing
#     the single string gets catastrophically wrong.
arm_rope() {
    local i e n=0 c=0 cur="" rest; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do
        _elem "$i"; cur+="$_E"$'\037'; n=$(( n + 1 ))
        if (( n % CHUNK == 0 )); then eval "_rp_${c}=\"\$cur\""; c=$(( c + 1 )); cur=""; fi
    done
    [[ -n "$cur" ]] && { eval "_rp_${c}=\"\$cur\""; c=$(( c + 1 )); }
    local k
    for (( k = 0; k < c; k++ )); do
        eval "rest=\"\$_rp_${k}\""
        while [[ -n "$rest" ]]; do
            e="${rest%%$'\037'*}"; rest="${rest#*$'\037'}"; _ck "$e"
        done
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        local want=$(( i * ELEMS / LOOKUPS )) j=0
        eval "rest=\"\$_rp_$(( want / CHUNK ))\""
        while (( j < want % CHUNK )); do rest="${rest#*$'\037'}"; j=$(( j + 1 )); done
        e="${rest%%$'\037'*}"; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$n"
}

# C3: a string while it is being built, split into slots the first time
#     somebody indexes it.
#
#     The two halves of the real use pattern want opposite things: appending
#     wants a string and indexing wants slots. This pays the string's cheap
#     append, then converts once, on the first index, and every index after
#     that is a slot read. A list that is only ever appended to and walked
#     never pays the conversion at all.
arm_hybrid() {
    local s="" i e n=0 rest split=0; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; s+="$_E"$'\037'; n=$(( n + 1 )); done
    rest="$s"
    while [[ -n "$rest" ]]; do
        e="${rest%%$'\037'*}"; rest="${rest#*$'\037'}"; _ck "$e"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        if (( split == 0 )); then
            local j=0; rest="$s"
            while [[ -n "$rest" ]]; do
                eval "_hy_${j}=\"\${rest%%\$'\037'*}\""
                rest="${rest#*$'\037'}"; j=$(( j + 1 ))
            done
            split=1
        fi
        eval "e=\"\$_hy_$(( i * ELEMS / LOOKUPS ))\""; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$n"
}

# D: the positional parameters.
#
#    The one list POSIX sh has natively, and the only arm here that needs no
#    eval and no scan. It costs the parameters themselves, so a function using
#    it cannot also read its own arguments, and there is exactly one per scope.
#    Whether that is affordable is a design question; what it costs is this.
arm_positional() {
    local i e; _SUM=0
    set --
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; set -- "$@" "$_E"; done
    for e in "$@"; do _ck "$e"; done
    for (( i = 0; i < LOOKUPS; i++ )); do
        eval "e=\"\${$(( i * ELEMS / LOOKUPS + 1 ))}\""; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$#"
}

# C4: a string while it is being built, split by the shell itself on read.
#
#     Every string arm above splits in a shell loop, one parameter expansion
#     per element, and every one of them loses badly for it. The shell will do
#     that split in C: setting `IFS` to the separator and writing `set -- $s`
#     is field splitting, which is what the shell does to every unquoted
#     expansion anyway.
#
#     So appending is a concatenation, splitting is one native pass, indexing
#     is a positional parameter, and the length is `$#`. Nothing is evaluated
#     and nothing is scanned.
#
#     Two things it needs and they are both one line. `set -f` because field
#     splitting is followed by pathname expansion and an element holding `*`
#     would otherwise become the directory listing. And `IFS` set to the
#     separator alone, not left at its default, or every space and newline in
#     an element splits it further, which the two awkward elements here would
#     catch immediately.
arm_native_split() {
    local s="" i e n=0; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; s+="$_E"$'\037'; n=$(( n + 1 )); done
    local oldifs="$IFS"
    set -f; IFS=$'\037'
    set -- $s
    IFS="$oldifs"; set +f
    for e in "$@"; do _ck "$e"; done
    for (( i = 0; i < LOOKUPS; i++ )); do
        eval "e=\"\${$(( i * ELEMS / LOOKUPS + 1 ))}\""; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$#"
}

# C5: the same native split, walked by shifting rather than by `for`.
#
#     `shift` is how POSIX sh consumes a list it cannot index, and it needs no
#     `eval` at all: `$1` is always the next element. What it costs is the list,
#     since consuming it destroys it, so this is a walk mechanism rather than an
#     access one and the indexing below still splits again to get its element.
arm_native_shift() {
    local s="" i e n=0; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; s+="$_E"$'\037'; n=$(( n + 1 )); done
    local oldifs="$IFS"
    set -f; IFS=$'\037'
    set -- $s
    IFS="$oldifs"; set +f
    n=$#
    while [[ $# -gt 0 ]]; do _ck "$1"; shift; done
    set -f; IFS=$'\037'
    set -- $s
    IFS="$oldifs"; set +f
    for (( i = 0; i < LOOKUPS; i++ )); do
        eval "e=\"\${$(( i * ELEMS / LOOKUPS + 1 ))}\""; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$n"
}

# D2: one string, built by prepending, walked in the order it was appended.
#
#     Whether a shell's string concatenation is asymmetric. If a prepend copies
#     where an append extends in place, this loses badly; if both copy, they
#     match and the reversal is the only difference. The reversal is real work
#     and is done rather than skipped, which is what the order-sensitive
#     checksum is there to enforce.
arm_prepend() {
    local s="" i e n=0 rest; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; s=$'\037'"$_E$s"; n=$(( n + 1 )); done
    # The last element appended sits at the front, so taking from the tail
    # yields the list in the order it was built and no reversal pass is needed.
    # An earlier version of this arm collected into a bash array to reverse,
    # which is the thing being given up, and it got the order backwards as
    # well. The rolling checksum refused the run, which is what it is for.
    rest="$s"
    while [[ -n "$rest" ]]; do
        e="${rest##*$'\037'}"; rest="${rest%$'\037'*}"; _ck "$e"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        local want=$(( i * ELEMS / LOOKUPS )) j=0
        rest="$s"
        while (( j < want )); do rest="${rest%$'\037'*}"; j=$(( j + 1 )); done
        e="${rest##*$'\037'}"; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$n"
}



# -----------------------------------------------------------------------------
# The walk-only arms. Append, then walk once. No indexing.
# -----------------------------------------------------------------------------

arm_w_bash() {
    local -a a=(); local i e; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; a+=("$_E"); done
    for e in "${a[@]}"; do _ck "$e"; done
    printf '%s|%s' "$_SUM" "${#a[@]}"
}

arm_w_slots() {
    local i e n=0; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; eval "_we_${i}=\"\$_E\""; n=$(( n + 1 )); done
    for (( i = 0; i < n; i++ )); do eval "e=\"\$_we_${i}\""; _ck "$e"; done
    printf '%s|%s' "$_SUM" "$n"
}

# The one that needs no positional parameters at all.
#
# `for e in $s` field-splits exactly the way `set -- $s` does, in C, and never
# touches `$@`. So the one-list-per-scope objection that the positional
# parameters carry does not apply to walking, only to indexing, and walking is
# what most of the real uses do.
arm_w_forin() {
    local s="" i e n=0; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; s+="$_E"$'\037'; n=$(( n + 1 )); done
    local oldifs="$IFS"
    # `IFS` and `set -f` are restored once, after the loop, not on every
    # iteration. An earlier version of this arm restored them inside the body
    # and paid for it: the body does not word-split anything, so it does not
    # care what `IFS` holds. A loop body that does call something splitting an
    # unquoted expansion would have to, and that is a real constraint on the
    # shape rather than an artefact of this bench.
    set -f; IFS=$'\037'
    for e in $s; do _ck "$e"; done
    IFS="$oldifs"; set +f
    printf '%s|%s' "$_SUM" "$n"
}

arm_w_shift() {
    local s="" i n=0; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; s+="$_E"$'\037'; n=$(( n + 1 )); done
    local oldifs="$IFS"
    set -f; IFS=$'\037'
    set -- $s
    IFS="$oldifs"; set +f
    n=$#
    while [[ $# -gt 0 ]]; do _ck "$1"; shift; done
    printf '%s|%s' "$_SUM" "$n"
}

arm_w_scan() {
    local s="" i e n=0 rest; _SUM=0
    for (( i = 0; i < ELEMS; i++ )); do _elem "$i"; s+="$_E"$'\037'; n=$(( n + 1 )); done
    rest="$s"
    while [[ -n "$rest" ]]; do
        e="${rest%%$'\037'*}"; rest="${rest#*$'\037'}"; _ck "$e"
    done
    printf '%s|%s' "$_SUM" "$n"
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

bench_arm "bash declare -a, append"      arm_bash_array
bench_arm "bash declare -a, by index"   arm_bash_by_index
bench_arm "slots by index"              arm_slots
bench_arm "slots, appends batched"      arm_slots_batched
bench_arm "slots, one extra eval"        arm_slots_double_eval
bench_arm "rope, chunked strings"       arm_rope
bench_arm "string then split on index"  arm_hybrid
bench_arm "string, split by the shell"   arm_native_split
bench_arm "string, split then shifted"   arm_native_shift
bench_arm "one string, unit-separated"  arm_one_string  1000
bench_arm "one string, prepended"       arm_prepend     1000
bench_arm "positional parameters"       arm_positional  4000

bench_run || exit 1

# A second case, because indexing and walking want opposite things and the
# table above mixes them. Reading the real uses, most lists are appended to and
# then walked once and never indexed at all: `_BENCH_LABEL`, `seen`, the toml
# accumulators. This is that shape on its own, and it is the one the floor
# actually has to serve well.
bench_reset

bench_case "The same list, appended to and walked, never indexed"
bench_size "$ELEMS"
bench_verify _answer_of

bench_arm "bash declare -a"             arm_w_bash
bench_arm "slots by index"              arm_w_slots
bench_arm "string, for over the split"  arm_w_forin
bench_arm "string, split then shifted"  arm_w_shift
bench_arm "one string, scanned"         arm_w_scan   4000

bench_run || exit 1

printf '\n'
printf 'Indexed arrays are in thirteen of the twenty files that cannot yet be\n'
printf 'read, against nine for associative arrays. This is the larger half.\n'
