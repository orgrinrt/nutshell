#!/usr/bin/env bash
# Tests for the bench harness.
#
# Three of its controls are the reason it exists rather than a timing loop, so
# each of them is shown refusing here. A harness whose controls have never been
# seen to fire is a harness nobody has any reason to trust, and the failure it
# is guarding against is the one where a number gets published.
#
# The timings themselves are not asserted. What a run measures depends on the
# machine, and a test that pinned a millisecond count would be a test of this
# laptop.

use test
use bench

# The clearing half is `bench_reset`, which is the harness's own and is what a
# bench file with two cases calls. This adds only what a test needs on top: a
# lower repeat count and a results directory that gets thrown away.
_bench_fresh() {
    bench_reset
    BENCH_REPEATS=2
    BENCH_RESULTS="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-bench.XXXXXX")"
    export BENCH_RESULTS
    _CLOCK_AT="$(mktemp "${TMPDIR:-/tmp}/nutshell-clock.XXXXXX")"
    BENCH_CLOCK=_pinned_clock
    _pin_runs 5
}
_bench_done() {
    rm -rf "$BENCH_RESULTS"; unset BENCH_RESULTS
    rm -f "$_CLOCK_AT"; unset _CLOCK_AT
    BENCH_CLOCK=_bench_clock_ns
}

# The clock every arm below runs on, which says what it is told.
#
# The arms used to spin for a few milliseconds each and go through `date`,
# which is two forks and most of the measurement, so a busy machine pushed the
# worst run past twice the best and the harness refused the run. It was right
# to: that refusal is what stops a ratio being read off a machine that cannot
# support one. But an arm about the report, or about a reset, was then failing
# for the weather, about one run in ten inside the full suite, and the two
# refusals that are about the machine had no arms at all, because nothing could
# make them happen on purpose.
#
# `_pin_runs` states each run's duration in milliseconds. The clock hands out a
# start and an end per run and repeats the last duration once the list is out,
# so an arm names the timings it cares about rather than counting reads. The
# counter lives in a file because every read happens inside a command
# substitution and a variable set there does not come back.
_pin_runs() { _CLOCK_MS=("$@"); printf '0' > "$_CLOCK_AT"; }

_pinned_clock() {
    local i at ms
    i="$(cat "$_CLOCK_AT")"
    at=$(( i / 2 ))
    (( at >= ${#_CLOCK_MS[@]} )) && at=$(( ${#_CLOCK_MS[@]} - 1 ))
    ms="${_CLOCK_MS[$at]}"
    if (( i % 2 == 0 )); then printf '%s' "$(( at * 1000000000 ))"
    else printf '%s' "$(( at * 1000000000 + ms * 1000000 ))"; fi
    printf '%s' "$(( i + 1 ))" > "$_CLOCK_AT"
}

# Two arms that agree, and one that does not. What they answer is the whole of
# what they are for now; how long they take is the clock's to say.
_arm_a()      { printf 'the same'; }
_arm_b()      { printf 'the same'; }
_arm_liar()   { printf 'something else'; }
_answer_of()  { "$1"; }

# --- it measures at all ------------------------------------------------------

#[test]
it_measures_two_arms_that_agree() {
    # The positive control. Every refusal below is worth nothing without it,
    # because a harness that refused everything would pass all of them.
    _bench_fresh
    bench_case "two arms"
    bench_verify _answer_of
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b

    local out; out="$(bench_run 2>&1)"
    local rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "two arms"
    assert_contains "$out" "best ms"
    _bench_done
}

# --- the arms have to agree --------------------------------------------------

#[test]
it_refuses_a_run_whose_arms_answer_differently() {
    # The control that matters most. A fast wrong arm beats a slow right one on
    # every timing, and an implementation whose encoding collides two keys
    # looks excellent right up until somebody reads it.
    _bench_fresh
    bench_case "one of these is lying"
    bench_verify _answer_of
    bench_arm "a"    _arm_a
    bench_arm "liar" _arm_liar

    local out rc=0; out="$(bench_run 2>&1)" || rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "disagree"
    # And it names both sides, because "they disagree" sends the reader to look
    # at ten arms.
    assert_contains "$out" "liar"
    assert_contains "$out" "a"
    # Nothing is published from a run that could not be compared.
    assert_empty "$(ls "$BENCH_RESULTS" 2>/dev/null)"
    _bench_done
}

#[test]
it_refuses_a_run_with_no_way_to_ask_an_arm_what_it_answered() {
    # Without this the check above cannot run at all, so the harness declines
    # rather than silently skipping it, which is what an optional control
    # becomes.
    _bench_fresh
    bench_case "no verify"
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b

    local out rc=0; out="$(bench_run 2>&1)" || rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "verify"
    _bench_done
}

# --- a bench needs a competitor ----------------------------------------------

#[test]
it_refuses_one_arm_timed_against_nothing() {
    # The commonest way a bench says nothing: one implementation measured on
    # its own, or against a version of itself somebody wrote worse on purpose.
    _bench_fresh
    bench_case "alone"
    bench_verify _answer_of
    bench_arm "a" _arm_a

    local out rc=0; out="$(bench_run 2>&1)" || rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "competitor"
    _bench_done
}

#[test]
it_refuses_a_run_that_never_said_what_it_was_measuring() {
    _bench_fresh
    bench_verify _answer_of
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b

    local out rc=0; out="$(bench_run 2>&1)" || rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "case"
    _bench_done
}

# --- what it leaves behind ---------------------------------------------------

#[test]
it_writes_the_numbers_and_the_conditions_they_were_taken_under() {
    # Both, and neither is enough alone. A row of milliseconds with no bash
    # version, host or size is a number that travels without its conditions,
    # which is the thing this harness exists to stop.
    _bench_fresh
    bench_case "kept"
    bench_size 123
    bench_verify _answer_of
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b
    bench_run >/dev/null 2>&1 || { _bench_done; _test_failed "the run itself refused"; return 1; }

    local csv meta
    csv="$(ls "$BENCH_RESULTS"/*.csv 2>/dev/null | head -1)"
    meta="$(ls "$BENCH_RESULTS"/*.meta 2>/dev/null | head -1)"
    assert_ne "$csv" ""
    assert_ne "$meta" ""

    local c m; c="$(cat "$csv")"; m="$(cat "$meta")"
    assert_contains "$c" "arm,best_ms,worst_ms"
    assert_contains "$c" "a,"
    assert_contains "$c" "b,"
    assert_contains "$m" "size      123"
    assert_contains "$m" "baseline  a"
    assert_contains "$m" "${BASH_VERSION}"
    assert_contains "$m" "$(uname -s)"
    _bench_done
}

#[test]
it_says_an_arm_was_not_run_rather_than_leaving_it_out() {
    # A skipped arm still gets a row. Dropping it makes the table read as
    # though that alternative was never considered, which is the other way a
    # bench misleads: not by a wrong number but by an absent one.
    _bench_fresh
    bench_case "ceilings"
    bench_size 100
    bench_verify _answer_of
    bench_arm "a"       _arm_a
    bench_arm "too big" _arm_b 10

    local out; out="$(bench_run 2>&1)"
    assert_contains "$out" "too big"
    assert_contains "$out" "not run at this size"

    local c; c="$(cat "$BENCH_RESULTS"/*.csv)"
    assert_contains "$c" "too big,-,-,-,no"
    _bench_done
}

#[test]
it_uses_the_note_an_arm_gave_for_why_it_did_not_run() {
    _bench_fresh
    bench_case "notes"
    bench_size 100
    bench_verify _answer_of
    bench_arm "a"      _arm_a
    bench_arm "absent" _arm_b 10 "no memory filesystem here"

    assert_contains "$(bench_run 2>&1)" "no memory filesystem here"
    _bench_done
}

# --- a second case in one file -----------------------------------------------

#[test]
it_clears_the_arms_so_a_second_case_can_run() {
    # Two workloads are two questions. Without this a file asking both declares
    # its second pair on top of its first, and the agreement control refuses
    # the run because arms answering different strings are not competing.
    _bench_fresh
    bench_case "the first question"
    bench_verify _answer_of
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b
    bench_run >/dev/null 2>&1

    bench_reset
    # All four, not just the functions. They are parallel arrays read by index
    # when the table is printed, so a reset clearing one and not another
    # desynchronises them and a check on `_BENCH_FN` alone would not see it.
    assert_eq "${#_BENCH_FN[@]}" "0"
    assert_eq "${#_BENCH_LABEL[@]}" "0"
    assert_eq "${#_BENCH_CEIL[@]}" "0"
    assert_eq "${#_BENCH_NOTE[@]}" "0"
    assert_eq "$BENCH_TITLE" ""
    assert_eq "$BENCH_VERIFY" ""
    assert_eq "$BENCH_SIZE" "0"
    _bench_done
}

#[test]
it_refuses_a_second_case_that_does_not_name_itself() {
    # The reset clears the title and the verify function too, so a second case
    # cannot inherit them. A file that resets and then declares arms without
    # naming the new question is refused rather than reported under the
    # previous one's heading.
    _bench_fresh
    bench_case "the first question"
    bench_verify _answer_of
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b
    bench_run >/dev/null 2>&1

    bench_reset
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b
    local out; out="$(bench_run 2>&1)"; local rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "no case named"
    _bench_done
}

#[test]
it_runs_a_second_case_after_a_reset() {
    # The positive control for the two refusals above. A reset that cleared
    # everything and left the harness unusable would pass both of them.
    _bench_fresh
    bench_case "the first question"
    bench_verify _answer_of
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b
    bench_run >/dev/null 2>&1

    bench_reset
    bench_case "the second question"
    bench_verify _answer_of
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b
    local out; out="$(bench_run 2>&1)"; local rc=$?
    assert_eq "$rc" "0"
    assert_contains "$out" "the second question"
    assert_not_contains "$out" "the first question"
    _bench_done
}

# --- the two refusals that are about the machine ------------------------------
#
# Both were written, reasoned about and never exercised, because the thing that
# causes them is the machine and nobody could ask the machine for it. With the
# clock saying the timings they are ordinary arms, and the run that used to
# trip them by accident no longer can.

#[test]
it_refuses_a_baseline_that_measured_nothing() {
    # A ratio against zero is not a number, so the run says so and prints no
    # table rather than printing one nobody can read.
    _bench_fresh
    _pin_runs 0
    bench_case "too fast to time"
    bench_verify _answer_of
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b
    local out; out="$(bench_run 2>&1)"; local rc=$?
    _bench_done
    assert_eq "$rc" "1"
    assert_contains "$out" "the baseline did not measure"
    assert_not_contains "$out" "against the first"
}

#[test]
it_refuses_a_baseline_that_moved_more_than_twice_across_its_runs() {
    # The baseline's own two runs are 5ms and 20ms, which is the machine
    # saying it cannot hold still. Reported with the ranges, because a reader
    # who wanted the numbers anyway should see how far apart they were.
    _bench_fresh
    _pin_runs 5 20
    bench_case "a noisy machine"
    bench_verify _answer_of
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b
    local out; out="$(bench_run 2>&1)"; local rc=$?
    _bench_done
    assert_eq "$rc" "1"
    assert_contains "$out" "too noisy"
    assert_contains "$out" "5"
    assert_contains "$out" "20"
    assert_not_contains "$out" "against the first"
}

#[test]
it_takes_a_ratio_when_the_arms_are_far_enough_apart() {
    # The positive control for both refusals, and the only arm that reads a
    # ratio at all: the baseline holds at 5ms across its runs and the second
    # arm sits at 20ms, which is outside it in the only direction that counts.
    _bench_fresh
    _pin_runs 5 5 20 20
    bench_case "one arm is slower"
    bench_verify _answer_of
    bench_arm "a" _arm_a
    bench_arm "b" _arm_b
    local out; out="$(bench_run 2>&1)"; local rc=$?
    _bench_done
    assert_eq "$rc" "0"
    assert_contains "$out" "400%"
    # And the baseline says nothing about itself, since its own range is its
    # own range and overlapping ranges are exactly what "within the noise"
    # means. Kept as an assertion because it looks like a defect and is not.
    assert_contains "$out" "within the noise"
}

# --- and the clock the harness ships ------------------------------------------

#[test]
it_reads_a_clock_that_only_goes_forward() {
    # Everything above says what the time was, so this is the one arm that
    # asks the machine, and it asks for the least that can be asked: two reads
    # in nanoseconds, the second not before the first. A ratio here would be
    # the weather again.
    local a b
    a="$(_bench_clock_ns)"
    b="$(_bench_clock_ns)"
    assert_ne "$a" ""
    assert_ne "$b" ""
    assert_ok test "$b" -ge "$a"
    # Nanoseconds rather than seconds, which is the whole reason the harness
    # asks for `%N`: a second-resolution clock would make every arm zero.
    assert_ok test "${#a}" -ge 18
}
