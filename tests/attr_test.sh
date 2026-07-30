#!/usr/bin/env bash
# Tests for the attribute reader.

use attr test

FIXTURE="${BASH_SOURCE[0]%/*}/fixtures/attributed.sh"

#[test]
it_finds_an_attribute_on_a_definition() {
    assert_ok attr_has "$FIXTURE" marked_fn pub
}

#[test]
it_does_not_invent_one_that_is_absent() {
    # The control. Every other assertion here would hold for a reader that
    # answered yes to everything.
    assert_fails attr_has "$FIXTURE" plain_fn pub
}

#[test]
it_reads_across_an_intervening_doc_comment() {
    # Attributes sit above the prose, not glued to the definition, so a reader
    # that stopped at the first comment would work only on undocumented code.
    assert_ok attr_has "$FIXTURE" documented_fn pub
}

#[test]
it_reads_the_argument() {
    assert_eq "$(attr_arg "$FIXTURE" limited_fn allow)" "loc = 400"
}

#[test]
it_reads_a_scoped_visibility() {
    assert_eq "$(attr_arg "$FIXTURE" internal_fn pub)" "lib"
}

#[test]
it_does_not_carry_an_attribute_past_real_code() {
    # A marker followed by a statement belongs to nothing. Carrying it onward
    # would silently mark whatever came next.
    assert_fails attr_has "$FIXTURE" after_code_fn pub
}

#[test]
it_finds_every_definition_with_a_given_attribute() {
    assert_eq "$(attr_find "$FIXTURE" test | tr '\n' ' ')" "a_test_fn b_test_fn "
}

#[test]
it_tells_two_arguments_of_one_attribute_apart() {
    # `#[allow(trivial_wrapper)]` and `#[allow(loc = 400)]` are not the same
    # marker. Matching on the name alone would let a size exemption excuse a
    # wrapper, which is the check the argument exists to scope.
    assert_eq "$(attr_arg "$FIXTURE" wrapper_allowed allow)" "trivial_wrapper"
    assert_eq "$(attr_arg "$FIXTURE" big_but_allowed allow)" "loc = 400"
}
