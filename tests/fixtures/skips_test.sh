#!/usr/bin/env bash
# Fixture for test_test.sh, run through the runner and read from its output. Not
# collected as part of the suite: the runner is only pointed at it by name.
# One test skips with a reason, one fails before it skips, one fails after it
# skips, and one passes: only the two failures may fail the run.

use test

#[test]
it_skips_for_want_of_a_tool() {
    skip "no frobnicator on this machine"
    return 0
}

#[test]
it_fails_before_it_skips() {
    assert_eq "a" "b"
    skip "this must not hide the failure"
}

#[test]
it_fails_after_a_skip_and_stays_failed() {
    skip "skipped, and then something broke"
    assert_eq "a" "b"
}

#[test]
it_passes() {
    assert_eq "a" "a"
}
