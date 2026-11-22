#!/usr/bin/env bash
# A fixture for `test_test.sh`. One test skips with a reason and one skips
# after an assertion failed, so the harness has a skip to report and a failure
# a skip must not hide. It is not part of the suite and is run by name.
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
