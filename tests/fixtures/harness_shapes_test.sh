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
