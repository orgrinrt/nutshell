#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/attr-scan - Reading attributes, regex against case
# =============================================================================
#
# `attr.sh` is the checker's hot path. Every check that asks whether a function
# is marked walks the file it lives in, one line at a time, and asks about
# each line: is this an attribute, and does this define something. At a quarter
# of a million lines across the library that inner test is the check.
#
# It was `[[ =~ ]]` with `BASH_REMATCH`, which is fast and is bash. Putting the
# module on the POSIX floor means the same questions answered with `case` and
# parameter expansion, and the question this asks is what that costs.
#
# Three arms, not two, and the third is the one that answers it. Shipped
# against converted moves the predicate and the loop shape at once, and a
# comparison with two variables in it cannot say which one did the work. The
# middle arm holds the loop and swaps only the predicate.
#
# That is the missing-competitor case: the first version of this bench had two
# arms and concluded that `case` beats a regex, which the third arm refutes.
#
# Both arms load exactly one implementation and then answer the same questions
# over the same file list. The old one comes out of git rather than being
# reconstructed here, so the comparison is against what actually shipped.
#
# Usage:
#   ./bench attr-scan [passes]
# =============================================================================

use bench

PASSES="${1:-3}"

_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nut-attrscan.XXXXXX")"
trap 'rm -rf "$_TMP"' EXIT

# The shipped implementation, from the trunk this branch came off. Taken from
# git so the baseline is what was really there, not a reconstruction of it.
OLD="${_TMP}/attr.old.sh"
HYB="${NUTSHELL_ROOT}/benches/attr-scan/hybrid.sh"
NEW="${NUTSHELL_ROOT}/lib/attr.sh"
if ! git -C "$NUTSHELL_ROOT" show "dev:lib/attr.sh" > "$OLD" 2>/dev/null; then
    printf 'bench: cannot read the old attr.sh out of git, so there is nothing to compare against\n' >&2
    exit 1
fi

# Real files, because the cost is per line and the mix of attribute lines,
# definitions, prose and blanks is what a real file has. A synthetic file of
# nothing but attributes would measure a case the checker never sees.
FILES=""
for f in "${NUTSHELL_ROOT}"/lib/*.sh; do
    [ -f "$f" ] && FILES="${FILES} ${f}"
done
LINES="$(cat $FILES | wc -l | tr -d ' ')"

# What both arms do. Defined before either implementation is loaded, so it
# binds to whichever one the arm sourced.
#
# `attr_find` is the shape the checker actually runs: one pass over a whole
# file asking about every line, rather than one lookup of one known function.
_workload() {
    local pass f
    pass=0
    while [ "$pass" -lt "$PASSES" ]; do
        for f in $FILES; do
            attr_find "$f" pub
            attr_find "$f" test
        done
        pass=$(( pass + 1 ))
    done
}

# A subshell each, so the two implementations never share a shell. They define
# the same names, so loading both would leave whichever came second answering
# for both arms and the bench would report a tie it invented.
arm_old() { ( . "$OLD" >/dev/null 2>&1; _workload ); }
arm_new() { ( . "$NEW" >/dev/null 2>&1; _workload ); }
arm_hyb() { ( . "$HYB" >/dev/null 2>&1; _workload ); }

# The control the harness refuses a run without. Both arms have to name the
# same functions in the same order, or one of them is faster because it is
# finding less.
answer_of() {
    local out; out="$("$1" 2>/dev/null)"
    # A silent arm is not an answer. Two arms that both find nothing agree
    # perfectly and the control passes, which would report a comparison of
    # nothing as a comparison. It is not vacuous today, both arms name 417
    # functions, and nothing here established that until this line.
    [ -n "$out" ] || { printf 'EMPTY'; return 0; }
    printf '%s' "$out" | sort | cksum
}

bench_case "reading attributes over ${LINES} lines of the library, ${PASSES} passes"
bench_size "$LINES"
bench_verify answer_of
bench_arm "bash regex, shipped loop"  arm_old
bench_arm "bash regex, new loop"      arm_hyb
bench_arm "posix case, new loop"      arm_new
bench_run || exit 1
