#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/bench.sh - Measuring one thing against its real alternatives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0: depends on nothing but bash and a nanosecond clock.
#
# A bench is several arms answering one question, measured on one input, with
# a record left behind that somebody can compare against instead of rerunning.
# What it is not is a timing loop: those answer once, for whoever ran them, and
# the number then travels without its conditions.
#
# Three controls are compulsory here rather than optional, because each of them
# has already let a wrong number through somewhere.
#
#   The arms have to agree. A fast arm giving a different answer is not a
#   competitor, and an implementation whose encoding collides two keys looks
#   excellent right up until somebody reads it. `bench_verify` names how to ask
#   an arm for its answer and nothing runs without one.
#
#   The baseline has to be steady. A ratio against a number that moved by a
#   factor of two across its own repeats is arithmetic rather than a
#   measurement, and the raw times get printed instead.
#
#   Two arms that overlap are not distinguishable. Where the ranges cross, the
#   honest report is that they cross, not a percentage computed from the
#   midpoints.
#
# And there has to be a real competitor. An arm beating a version of itself
# somebody wrote worse on purpose establishes that the author can write worse
# on purpose. `bench_run` refuses a single arm.
#
# Usage:
#   use bench
#
#   bench_case "what a map costs without bash arrays"
#   bench_verify answer_of              # every arm must return the same
#   bench_arm "bash declare -A" arm_assoc
#   bench_arm "eval names"      arm_eval  4000     # ceiling: skip above this
#   bench_size 9606
#   bench_run
# =============================================================================

nut_once || return 0

declare -g  BENCH_TITLE=""
declare -g  BENCH_VERIFY=""
declare -g  BENCH_SIZE=0
declare -g  BENCH_REPEATS="${BENCH_REPEATS:-7}"
declare -ga _BENCH_LABEL=()
declare -ga _BENCH_FN=()
declare -ga _BENCH_CEIL=()
declare -ga _BENCH_NOTE=()

#[pub]
# Name the question this bench answers. The first line of every report and of
# every record it writes.
# Usage: bench_case "what a map costs without bash arrays"
bench_case() { BENCH_TITLE="$*"; }

#[pub]
# How to ask an arm what answer it produced.
#
# Compulsory, and the control that matters most: without it a bench compares a
# fast wrong arm against a slow right one and reports the wrong one winning.
# The function is called with an arm's name and prints whatever that arm
# computed; every arm has to print the same thing.
# Usage: bench_verify answer_of
bench_verify() { BENCH_VERIFY="$1"; }

#[pub]
# How many items the input holds. Recorded rather than used, because a number
# without the size it was taken at cannot be compared to another number.
# Usage: bench_size 9606
bench_size() { BENCH_SIZE="$1"; }

#[pub]
# One arm. The first declared is the baseline every ratio is against.
#
# A ceiling above zero means the arm is skipped when the size passes it, which
# is stated in the table rather than hidden: which arms have a ceiling at all
# is itself a result.
# Usage: bench_arm "bash declare -A" arm_assoc [ceiling] [note]
bench_arm() {
    _BENCH_LABEL+=("$1")
    _BENCH_FN+=("$2")
    _BENCH_CEIL+=("${3:-0}")
    _BENCH_NOTE+=("${4:-}")
}

#[pub]
# Clear the arms so a second case can be declared in the same file.
#
# Two workloads are two questions, and the agreement control is right to refuse
# them as one comparison: arms that answer different strings are not competing.
# A file that wants to ask both declares its arms, runs, resets, and declares
# the next set.
#
# Cleared: the arms, their labels, ceilings and notes, the title, the verify
# function and the size. So a second case has to name its own question and
# cannot inherit a baseline from the first by accident.
#
# Not cleared: `BENCH_REPEATS` and `BENCH_RESULTS`, which describe how the run
# is taken rather than what it asks. Naming what is cleared beats saying
# nothing carries over, which was the earlier wording and was false.
# Usage: bench_run; bench_reset; bench_case "the next question"
bench_reset() {
    _BENCH_LABEL=(); _BENCH_FN=(); _BENCH_CEIL=(); _BENCH_NOTE=()
    BENCH_TITLE=""; BENCH_VERIFY=""; BENCH_SIZE=0
}

# One run of one arm, in milliseconds.
_bench_once() {
    local fn="$1" start end
    start="$(date +%s%N 2>/dev/null)" || return 1
    "$fn" >/dev/null 2>&1
    end="$(date +%s%N 2>/dev/null)" || return 1
    printf '%s' "$(( (end - start) / 1000000 ))"
}

# The best and the worst of several runs, into _BENCH_BEST and _BENCH_WORST.
#
# The minimum is the estimator rather than the mean, because every source of
# noise here adds time and none removes it, so the fastest run is the one least
# disturbed. The spread is kept because a number without one cannot be compared
# against another number: four consecutive runs of one arm on this machine gave
# 5, 5, 35, 5, and a single timing would have reported any of them.
_bench_measure() {
    local fn="$1" i t
    _BENCH_BEST=""; _BENCH_WORST=""
    for (( i = 0; i < BENCH_REPEATS; i++ )); do
        t="$(_bench_once "$fn")" || return 1
        [[ -z "$_BENCH_BEST"  || "$t" -lt "$_BENCH_BEST"  ]] && _BENCH_BEST="$t"
        [[ -z "$_BENCH_WORST" || "$t" -gt "$_BENCH_WORST" ]] && _BENCH_WORST="$t"
    done
    return 0
}

# Every arm has to answer the same. Returns 1 naming the two that disagree.
_bench_agree() {
    local i want="" got="" first=""
    for (( i = 0; i < ${#_BENCH_FN[@]}; i++ )); do
        [[ "${_BENCH_SKIP[$i]:-0}" == "1" ]] && continue
        got="$("$BENCH_VERIFY" "${_BENCH_FN[$i]}")" || return 1
        [[ "$got" == "SKIP" ]] && continue
        if [[ -z "$first" ]]; then want="$got"; first="${_BENCH_LABEL[$i]}"; continue; fi
        if [[ "$got" != "$want" ]]; then
            printf 'the arms disagree, so this is not a comparison:\n' >&2
            printf '  %s answered %q\n' "${_BENCH_LABEL[$i]}" "$got" >&2
            printf '  %s answered %q\n' "$first" "$want" >&2
            return 1
        fi
    done
    [[ -n "$first" ]] || { printf 'no arm produced an answer to compare\n' >&2; return 1; }
    return 0
}

# Where a run's record goes. Beside the bench that produced it, in the repo,
# because a measurement nobody can find again is one somebody will take twice.
_bench_results_dir() {
    printf '%s' "${BENCH_RESULTS:-${PWD}/benches/results}"
}

# The record: one row per arm, plus the conditions it was taken under. Both
# matter and neither is enough alone.
_bench_record() {
    local dir stamp i
    dir="$(_bench_results_dir)"
    mkdir -p "$dir" 2>/dev/null || return 0
    stamp="$(date +%Y%m%d%H%M%S)"

    {
        printf 'arm,best_ms,worst_ms,ratio_to_baseline,ran\n'
        for (( i = 0; i < ${#_BENCH_LABEL[@]}; i++ )); do
            printf '%s,%s,%s,%s,%s\n' \
                "${_BENCH_LABEL[$i]//,/ }" \
                "${_BENCH_BESTS[$i]:--}" "${_BENCH_WORSTS[$i]:--}" \
                "${_BENCH_RATIO[$i]:--}" \
                "$( [[ "${_BENCH_SKIP[$i]:-0}" == "1" ]] && printf no || printf yes )"
        done
    } > "${dir}/${stamp}.csv"

    {
        printf 'case      %s\n' "$BENCH_TITLE"
        printf 'size      %s\n' "$BENCH_SIZE"
        printf 'repeats   %s\n' "$BENCH_REPEATS"
        printf 'baseline  %s\n' "${_BENCH_LABEL[0]:-none}"
        printf 'bash      %s\n' "${BASH_VERSION:-unknown}"
        printf 'host      %s %s\n' "$(uname -s)" "$(uname -m)"
        printf 'taken     %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "${dir}/${stamp}.meta"

    printf '%s' "${dir}/${stamp}"
}

#[pub]
# Measure every arm, run the controls, print the table, write the record.
#
# Returns 1 when a control refuses, which is a result rather than a failure of
# the harness: a bench that cannot support its numbers must not print them.
# Usage: bench_run -> 0 when it measured, 1 when a control refused
bench_run() {
    local i n="${#_BENCH_FN[@]}"

    [[ -n "$BENCH_TITLE" ]] || { printf 'bench: no case named\n' >&2; return 1; }
    [[ -n "$BENCH_VERIFY" ]] || {
        printf 'bench: no verify function, so the arms cannot be shown to agree\n' >&2
        printf '  an arm that is fast and wrong wins every bench without this\n' >&2
        return 1; }
    if (( n < 2 )); then
        printf 'bench: %s arm(s). A bench needs a real competitor, not one\n' "$n" >&2
        printf '  implementation timed against nothing.\n' >&2
        return 1
    fi

    declare -ga _BENCH_BESTS=() _BENCH_WORSTS=() _BENCH_SKIP=() _BENCH_RATIO=()
    for (( i = 0; i < n; i++ )); do
        if (( _BENCH_CEIL[i] > 0 && BENCH_SIZE > _BENCH_CEIL[i] )); then
            _BENCH_BESTS+=("-"); _BENCH_WORSTS+=("-"); _BENCH_SKIP+=(1); _BENCH_RATIO+=("-")
            continue
        fi
        _bench_measure "${_BENCH_FN[$i]}" || {
            printf 'bench: no nanosecond clock here, so nothing can be timed\n' >&2
            return 1; }
        _BENCH_BESTS+=("$_BENCH_BEST"); _BENCH_WORSTS+=("$_BENCH_WORST")
        _BENCH_SKIP+=(0); _BENCH_RATIO+=("-")
    done

    _bench_agree || return 1

    printf '%s\n\n' "$BENCH_TITLE"
    printf '  size      %s\n' "$BENCH_SIZE"
    printf '  repeats   %s\n' "$BENCH_REPEATS"
    printf '  bash      %s\n' "${BASH_VERSION:-unknown}"
    printf '  host      %s %s\n\n' "$(uname -s)" "$(uname -m)"

    local base_best="${_BENCH_BESTS[0]}" base_worst="${_BENCH_WORSTS[0]}"
    if [[ "$base_best" == "-" ]] || (( base_best <= 0 )); then
        printf '  the baseline did not measure, so nothing below can be a ratio\n' >&2
        return 1
    fi
    if (( base_worst > base_best * 2 )); then
        printf '  the baseline moved from %sms to %sms across %s runs.\n' \
            "$base_best" "$base_worst" "$BENCH_REPEATS" >&2
        printf '  this machine is too noisy right now for a ratio to mean anything.\n\n' >&2
        for (( i = 0; i < n; i++ )); do
            printf '  %-34s %6s..%-6s\n' "${_BENCH_LABEL[$i]}" \
                "${_BENCH_BESTS[$i]}" "${_BENCH_WORSTS[$i]}"
        done
        return 1
    fi

    printf '  %-34s %8s %11s  %s\n' "arm" "best ms" "spread" "against the first"
    for (( i = 0; i < n; i++ )); do
        if [[ "${_BENCH_SKIP[$i]}" == "1" ]]; then
            printf '  %-34s %8s %11s  %s\n' "${_BENCH_LABEL[$i]}" "-" "-" \
                "${_BENCH_NOTE[$i]:-not run at this size}"
            continue
        fi
        # A ratio only where the ranges do not overlap. Where they do, the arms
        # are not distinguishable at this size, and saying so is the answer.
        if (( _BENCH_BESTS[i] > base_worst )) || (( _BENCH_WORSTS[i] < base_best )); then
            _BENCH_RATIO[$i]="$(( _BENCH_BESTS[i] * 100 / base_best ))%"
        else
            _BENCH_RATIO[$i]="within the noise"
        fi
        printf '  %-34s %8s %11s  %s\n' "${_BENCH_LABEL[$i]}" \
            "${_BENCH_BESTS[$i]}" \
            "${_BENCH_BESTS[$i]}..${_BENCH_WORSTS[$i]}" \
            "${_BENCH_RATIO[$i]}"
    done

    local where; where="$(_bench_record)"
    [[ -n "$where" ]] && printf '\n  kept at %s.csv and .meta\n' "$where"
    return 0
}
