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

_bench_fresh() {
    BENCH_TITLE=""; BENCH_VERIFY=""; BENCH_SIZE=0; BENCH_REPEATS=2
    _BENCH_LABEL=(); _BENCH_FN=(); _BENCH_CEIL=(); _BENCH_NOTE=()
    BENCH_RESULTS="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-bench.XXXXXX")"
    export BENCH_RESULTS
}
_bench_done() { rm -rf "$BENCH_RESULTS"; unset BENCH_RESULTS; }

# Two arms that agree, and one that does not.
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
