#!/usr/bin/env bash
# A fixture, not part of the suite. Run by the harness's own tests.
#
# The file reads its stdin to the end when it is sourced, before any test runs.
# The harness reads the names still to run from its own stdin, so a file that
# shares it takes the rest of them and the run ends after the first test.

use test

cat >/dev/null

#[test]
it_is_the_first_of_three() {
    assert_eq "1" "1"
}

#[test]
it_is_the_second_of_three() {
    assert_eq "2" "2"
}

#[test]
it_is_the_third_of_three() {
    assert_eq "3" "3"
}
