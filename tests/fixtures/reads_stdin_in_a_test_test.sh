#!/usr/bin/env bash
# A fixture, not part of the suite. Run by the harness's own tests.
#
# The first test reads its stdin to the end. Sharing the harness's stdin, it
# takes the names of the two tests after it.

use test

#[test]
it_reads_its_stdin_to_the_end() {
    cat >/dev/null
    assert_eq "1" "1"
}

#[test]
it_still_runs_after_that() {
    assert_eq "2" "2"
}

#[test]
it_runs_last() {
    assert_eq "3" "3"
}
