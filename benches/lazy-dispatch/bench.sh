#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/lazy-dispatch - What deciding at first call costs
# =============================================================================
#
# `text_grep` and its twelve siblings are stubs. On the first call each one asks
# `deps_has` which tools are here, picks an implementation, `nut_reload`s the
# module holding it, and is replaced by it. Every call after that is the real
# function and costs nothing.
#
# So the cost is once per process and once per dispatched function, and a
# lowering knows the answer already: it can emit the chosen implementation and
# skip the deciding entirely. This prices that.
#
# **Each iteration is a fresh shell**, because the cost being measured is paid
# once and a loop inside one shell would measure it once and then measure
# nothing thirty times. That makes every arm pay for a shell start and an
# `init`, which is real and is the same on both sides.
#
# The workload calls a given number of distinct dispatched functions, because
# the cost is per function rather than per program: a script touching one of
# them pays once and a script touching all thirteen pays thirteen times.
#
# Usage:
#   ./bench lazy-dispatch [functions] [iterations]
# =============================================================================

use bench

FNS="${1:-4}"
ITERS="${2:-12}"
ROOT="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"

# The dispatched functions, in the order the workload reaches for them. All of
# them route through `deps_has` and a `nut_reload`.
ALL_FNS=(text_grep text_contains text_count_matches text_replace \
         text_match_first text_lines_matching)

_pick() {
    local i out=""
    for (( i = 0; i < FNS && i < ${#ALL_FNS[@]}; i++ )); do out+=" ${ALL_FNS[$i]}"; done
    printf '%s' "$out"
}

# A file the workload can work on, made once and shared by every arm.
_FIXTURE="$(mktemp "${TMPDIR:-/tmp}/nut-lazy.XXXXXX")"
{
    printf 'alpha one\nbeta two\ngamma three\n'
    printf 'delta four\nepsilon five\n'
} > "$_FIXTURE"
trap 'rm -f "$_FIXTURE"' EXIT

# -----------------------------------------------------------------------------
# The arms
# -----------------------------------------------------------------------------

# Each arm runs the same calls and prints the same answer, so an arm that
# skipped the deciding and got a different implementation shows up as a
# disagreement rather than as a win.
_body() {
    local fns; fns="$(_pick)"
    cat <<BODY
        . "${ROOT}/init" >/dev/null 2>&1 || exit 1
        use text
        out=""
        for fn in ${fns}; do
            case "\$fn" in
                text_grep)            out="\${out}\$(text_grep alpha "${_FIXTURE}" | wc -l)" ;;
                text_contains)        out="\${out}\$(text_contains beta "${_FIXTURE}" && echo y || echo n)" ;;
                text_count_matches)   out="\${out}\$(text_count_matches a "${_FIXTURE}")" ;;
                text_replace)         out="\${out}\$(text_replace one ONE "${_FIXTURE}" | wc -l)" ;;
                text_match_first)     out="\${out}\$(text_match_first gamma "${_FIXTURE}")" ;;
                text_lines_matching)  out="\${out}\$(text_lines_matching five "${_FIXTURE}" | wc -l)" ;;
            esac
        done
        printf '%s' "\$out"
BODY
}

# A: as it ships. Every dispatched function decides on its first call.
arm_lazy() {
    local i last=""
    for (( i = 0; i < ITERS; i++ )); do last="$(bash -c "$(_body)")"; done
    printf '%s' "$last"
}

# B: the deciding done once and its answer reused across the iterations.
#
#    **Not a lowering.** A lowering emits the chosen implementation into the
#    file and this cannot: it warms `deps`'s tool table in the parent and hands
#    it down through the environment, so each shell skips the tool lookups and
#    still runs the same `nut_reload`. That prices the `deps_has` half of the
#    deciding and not the module load, so it is a floor on what a lowering
#    saves rather than an estimate of it.
arm_warm_deps() {
    local i last="" pre=""
    # Every tool the dispatch stubs ask about, resolved once here.
    local t
    for t in grep sed awk perl; do
        if command -v "$t" >/dev/null 2>&1; then
            pre+="_TOOL_PATH_${t}=$(command -v "$t"); export _TOOL_PATH_${t}; "
        fi
    done
    for (( i = 0; i < ITERS; i++ )); do last="$(bash -c "${pre}$(_body)")"; done
    printf '%s' "$last"
}

# C: the implementation bound before the first call, which is the shape a
#    lowering emits. The stub never runs, so neither the tool lookups nor the
#    `nut_reload` happen.
arm_prebound() {
    local i last=""
    local pre='
        . "'"${ROOT}"'/init" >/dev/null 2>&1 || exit 1
        use text
        use text::impl::grep_match
        use text::impl::sed_replace
    '
    for (( i = 0; i < ITERS; i++ )); do
        last="$(bash -c "${pre}$(_body | tail -n +2)")"
    done
    printf '%s' "$last"
}

# -----------------------------------------------------------------------------
# The bench
# -----------------------------------------------------------------------------

_answer_of() { "$1"; }

bench_case "What deciding an implementation at first call costs"
bench_size "$FNS"
bench_verify _answer_of

bench_arm "decided at first call"      arm_lazy
bench_arm "tool table warmed"          arm_warm_deps
bench_arm "implementation pre-bound"   arm_prebound

bench_run || exit 1

printf '\n'
printf 'Each iteration is a fresh shell, because the cost is paid once per\n'
printf 'process. Thirteen functions dispatch this way; the default measures %s.\n' "$FNS"
