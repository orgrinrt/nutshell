#!/usr/bin/env bash
# Fixture for test_test.sh, run through the runner and read from its output. Not
# collected as part of the suite: the runner is only pointed at it by name.

use test

#[test]
it_skips_for_a_named_reason() {
    test_skip "the thing it needs is not here"
    return 0
}

#[test]
it_fails_after_a_skip_and_stays_failed() {
    test_skip "skipped, and then something broke"
    assert_eq "a" "b"
}

#[test]
it_passes() {
    assert_eq "a" "a"
}
