#!/usr/bin/env bash
# A fixture, not part of the suite. Run by the harness's own tests.

use test

#[test]
it_asserts_nothing_at_all() {
    local x=1
    : "$x"
}

#[test]
it_ends_on_a_command_that_returns_non_zero() {
    assert_eq "x" "x"
    # A perfectly ordinary last line. `grep -q` finding nothing is not a
    # failure of this test, and half the library returns non-zero on purpose.
    printf 'nothing\n' | grep -q "something"
}

#[test]
it_dies_part_way_through() {
    assert_eq "x" "x"
    exit 3
}

#[test]
it_forks_a_child_that_fails_late() {
    # The child outlives the test and writes its failure after the runner has
    # moved on. With one shared tally that landed on whichever test came next:
    # this one passed and an innocent one failed.
    ( sleep 1; assert_eq "a" "b" ) >/dev/null 2>&1 &
    assert_eq "x" "x"
}

#[test]
it_is_the_innocent_one_after_the_fork() {
    assert_eq "y" "y"
}
