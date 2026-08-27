#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/startup - What a lowered form saves at load time
# =============================================================================
#
# Every `use` resolves through `_lib_nut_lookup`, every caller of that wraps it
# in a command substitution, and a fork is not cheap. The cost sits in front of
# everything: it is paid before a line of anybody's script runs.
#
# The lowered arm here resolves `use` **at lower time** rather than stubbing it
# out. That is the difference between this and the first version of this bench,
# which concatenated the named modules only, never loaded their dependencies,
# and reported a number that was partly the arm doing less work.
#
# So the closure is walked: each module's file is read, its own `use` lines
# resolved, and so on until nothing new appears. What is emitted is every file
# the resolver would have sourced, in the order it would have sourced them.
# `use` is a no-op in the result because by then there is nothing left for it
# to do, which is a fact about the lowering rather than a shortcut.
#
# **The arms are held to the same surface by the harness.** `bench_verify`
# compares the sorted list of every function defined, so an arm that loaded
# less is a disagreement and the run is refused rather than reported. The first
# version compared one function's output, and both arms answered `str_upper ok`
# identically while differing by 76 functions.
#
# Usage:
#   ./bench startup [modules]
# =============================================================================

use bench

MODS="${1:-string log fs os toml validate}"

_ST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-st.XXXXXX")"
trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT

_ST_ROOT="${NUTSHELL_ROOT:-$PWD}"

# Every module a file reaches for, as the resolver would read them.
#
# `super::x` inside a unit means x in that unit, and the manifest names it by
# its full path, so the prefix is dropped and the leaf looked up. That is what
# `_use_resolve` does and this has to agree with it or the closure is short.
# The lowering is `bin/nut-lower`, not a copy of it.
#
# This bench had its own, which is how the tool was found: every gotcha in it
# was discovered here first, by getting it wrong and watching the harness
# refuse the run for arms that disagreed.
#
# Keeping the copy is what let this file publish a 3.7x win for tree-shaking
# that was not real. The copy dropped `_deps_init`, because nothing names it
# and it is called at file scope, so the artifact it measured had an empty tool
# table and skipped an eager scan the real library does. Correct answers by a
# slower path per lookup, so nothing could tell.
#
# So the numbers below are about the tool. If it regresses, this bench moves.
_ST_LOWER="${_ST_ROOT}/bin/nut-lower"
_ST_WORKLOAD="${_ST_ROOT}/benches/startup/workload.sh"
_ST_LOWERED="$_ST_TMP/lowered.sh"
_ST_SHAKEN="$_ST_TMP/shaken.sh"
_ST_NOPRE="$_ST_TMP/nopre.sh"

_st_lower() {
    "$_ST_LOWER" "$_ST_WORKLOAD" --use "${MODS// /,}" --no-shake -o "$_ST_LOWERED"
}

# The same lowering with the dispatch left to run at first call, which is what
# the tool did before it decided it here. The pair is what prices deciding it
# ahead of time: same concatenation, same resolution, same closure, and the
# only difference is whether `fs_size` is already the implementation when the
# file finishes loading or is still a stub that will go and fetch one.
_st_lower_nopre() {
    "$_ST_LOWER" "$_ST_WORKLOAD" --use "${MODS// /,}" --no-shake --no-prebind -o "$_ST_NOPRE"
}

_st_shake() {
    "$_ST_LOWER" "$_ST_WORKLOAD" --use "${MODS// /,}" -o "$_ST_SHAKEN"
}


# The lowered file with everything unreachable removed.
#
# Roots are the names the workload mentions. Then the closure: anything a
# retained body mentions is retained too. Whatever survives is emitted, the
# rest is not there at all.
#
# It reads names rather than parsing shell, so it over-retains: a name in a
# comment or a string counts. That is the safe direction, and the number it
# produces is a floor on what a real pass could drop rather than a claim about
# what it would.
#
# What it cannot do is see a name assembled at run time, which is why every
# `nut_reload` in this library is written literally. Two in `fs.sh` were not,
# and a shake would have dropped two of the three stat implementations.

# What the workload answers. The arms load the library three ways and this is
# what says they still do the same thing.
#
# Not the loaded surface, which is what the other comparison in this file uses:
# a shaken arm loads less by design, so comparing surfaces would refuse it for
# doing exactly what it is for.
_ST_PROBE='. "'"$_ST_WORKLOAD"'" >/dev/null 2>&1; _wl'

arm_resolved() {
    bash -c '
        . "$1"/init >/dev/null 2>&1 || exit 1
        for m in $2; do use "$m" >/dev/null 2>&1; done
        eval "$3"
    ' _ "$_ST_ROOT" "$MODS" "$_ST_PROBE" 2>/dev/null
}

arm_lowered() {
    bash -c '. "$1" >/dev/null 2>&1 || exit 1; eval "$2"' \
        _ "$_ST_LOWERED" "$_ST_PROBE" 2>/dev/null
}

arm_shaken() {
    bash -c '. "$1" >/dev/null 2>&1 || exit 1; eval "$2"' \
        _ "$_ST_SHAKEN" "$_ST_PROBE" 2>/dev/null
}

arm_lowered_nopre() {
    bash -c '. "$1" >/dev/null 2>&1 || exit 1; eval "$2"' \
        _ "$_ST_NOPRE" "$_ST_PROBE" 2>/dev/null
}

# The interpreter and nothing else, so the two above can be read against what
# is paid before any module is asked for at all.
arm_init_only() {
    bash -c '. "$1"/init >/dev/null 2>&1 || exit 1; printf init-only' \
        _ "$_ST_ROOT" 2>/dev/null
}

_st_lower
_st_lower_nopre
_st_shake

_answer_of() { "$1"; }

bench_case "What a lowered form saves at load time"
_ST_CLOSURE="$("$_ST_LOWER" "$_ST_WORKLOAD" --use "${MODS// /,}" --list | wc -l | tr -d " ")"
bench_size "$_ST_CLOSURE"
bench_verify _answer_of

bench_arm "resolved through the manifest"  arm_resolved
bench_arm "lowered, dispatch left to run"  arm_lowered_nopre
bench_arm "lowered, use resolved already"  arm_lowered
bench_arm "lowered and shaken"             arm_shaken

bench_run || exit 1

printf '\n'
printf 'The closure is %s files for the %s modules named.\n' \
    "$_ST_CLOSURE" "$(printf '%s\n' $MODS | wc -l | tr -d ' ')"
printf '\n'
printf 'The interpreter loads in both arms, so this is the resolution cost and\n'
printf 'not the cost of nutshell existing. `./bench startup` with one module\n'
printf 'shows how much of it is per-module rather than fixed.\n'
