#!/usr/bin/env bash
# A fixture, not part of the suite. Run by the harness's own tests.
#
# The first assertion fails and the last one passes. A harness that reports
# only a test function's exit status calls this green, because a function's
# status is its last command's.

use test

#[test]
it_should_be_reported_as_a_failure() {
    assert_eq "a" "b"
    assert_eq "x" "x"
}
