#!/usr/bin/env bash
# Tests for validation.
#
# Twenty-six functions were marked as this module's surface with nothing
# exercising any of them, and two were wrong in ways a single negative case
# would have caught.

use validate test

#[test]
it_recognises_an_address_of_eight_groups() {
    assert_ok is_ipv6 "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
    assert_ok is_ipv6 "2001:db8:85a3:0:0:8a2e:370:7334"
}

#[test]
it_recognises_a_compressed_address() {
    assert_ok is_ipv6 "::"
    assert_ok is_ipv6 "::1"
    assert_ok is_ipv6 "2001:db8::1"
    assert_ok is_ipv6 "fe80::"
}

#[test]
it_refuses_a_run_of_colons() {
    # The pattern this replaced allowed a group of zero to four hex digits
    # anywhere, so any run of colons matched: every group between them was
    # allowed to be empty.
    assert_fails is_ipv6 ":::::"
    assert_fails is_ipv6 ":::"
    assert_fails is_ipv6 "::::::::::"
}

#[test]
it_refuses_too_few_groups_without_compression() {
    # An address is eight groups. Without `::` every one has to be written.
    assert_fails is_ipv6 "1:2:3"
    assert_fails is_ipv6 "1:2:3:4:5:6:7"
}

#[test]
it_refuses_more_than_one_compression() {
    # `1::2::3` says nothing about where the zeroes go.
    assert_fails is_ipv6 "1::2::3"
}

#[test]
it_refuses_a_group_that_is_not_hex() {
    assert_fails is_ipv6 "2001:db8::xyz1"
    assert_fails is_ipv6 "2001:db8::12345"
}

#[test]
it_accepts_an_ordinary_hostname() {
    assert_ok is_hostname "example.com"
    assert_ok is_hostname "sub.domain.example.com"
    assert_ok is_hostname "a"
}

#[test]
it_refuses_a_label_over_sixty_three_characters() {
    # The pattern alone accepted a single label of any length, so a
    # 300-character name passed. A name that cannot be resolved is not a
    # hostname whatever it is made of.
    local long
    long="$(printf 'a%.0s' $(seq 64))"
    assert_fails is_hostname "$long"
    assert_fails is_hostname "${long}.com"

    local ok
    ok="$(printf 'a%.0s' $(seq 63))"
    assert_ok is_hostname "$ok"
}

#[test]
it_refuses_a_name_over_two_hundred_and_fifty_three_characters() {
    local long=""
    local i
    for i in $(seq 6); do long+="$(printf 'a%.0s' $(seq 50))."; done
    assert_fails is_hostname "${long}com"
}

#[test]
it_refuses_a_label_on_a_hyphen() {
    assert_fails is_hostname "-example.com"
    assert_fails is_hostname "example-.com"
    assert_fails is_hostname "example..com"
}

#[test]
it_judges_the_ordinary_shapes() {
    assert_ok is_integer "42"
    assert_ok is_integer "-42"
    assert_fails is_integer "4.2"
    assert_fails is_integer "x"

    assert_ok is_positive_integer "1"
    assert_fails is_positive_integer "0"
    assert_fails is_positive_integer "-1"

    assert_ok is_port "80"
    assert_ok is_port "65535"
    assert_fails is_port "65536"
    assert_fails is_port "0"

    assert_ok is_ipv4 "192.168.1.1"
    assert_fails is_ipv4 "256.1.1.1"
    assert_fails is_ipv4 "1.2.3"
}

#[test]
it_reads_truth_and_falsity() {
    assert_ok is_truthy "true"
    assert_ok is_truthy "1"
    assert_ok is_truthy "yes"
    assert_ok is_falsy "false"
    assert_ok is_falsy "0"
    assert_fails is_truthy "false"
}

#[test]
it_knows_set_from_empty() {
    # Both take the name of a variable, not its value.
    filled="x"
    empty=""
    assert_ok is_set filled
    assert_fails is_set empty
    assert_fails is_set never_assigned_anywhere
    assert_ok is_empty empty
    assert_fails is_empty filled
}

#[test]
it_answers_about_a_name_even_when_handed_a_value() {
    # The trap in taking a name. `is_empty "$x"` reads naturally and asks about
    # a variable named after the contents of x, which is almost never set, so
    # the answer is "empty" whatever x holds. Pinned so the shape is at least
    # written down, and so a change to it is a decision rather than a surprise.
    filled="x"
    assert_ok is_empty "$filled"
}
