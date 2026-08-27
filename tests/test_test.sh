#!/usr/bin/env bash
# Tests for the test harness itself, which had none.
#
# An assertion that cannot fail is worth nothing, and the way to find out is to
# make it fail on purpose. `_try` runs one in a subshell so its failure marks
# nothing in the enclosing run, and hands back the message and the status.

use test

# Run an assertion in isolation. Its output comes back on stdout and its status
# as the exit code, and neither the assert counter nor the failure counter of
# the test calling this is touched, because the subshell keeps them.
_try() {
    ( _test_mark() { :; }; "$@" ) 2>&1
}
_try_rc() {
    ( _test_mark() { :; }; "$@" ) >/dev/null 2>&1
}

#[test]
it_has_the_negation_of_contains() {
    # `assert_not_contains` was missing while `assert_contains` existed, so
    # three tests in this repo carried a line that was an unknown command: it
    # registered no assertion and each test passed on whatever else it checked.
    # Two of them reported a pass. The harness's own "asserted nothing" guard
    # caught the third, which is the only reason any were found.
    assert_not_contains "hello world" "PWNED"
    assert_contains "hello world" "world"
}

#[test]
it_fails_both_directions_of_contains_when_it_should() {
    # The negative control. Without it the two above pass against an assertion
    # that returns zero unconditionally, which is exactly the defect being
    # repaired.
    assert_fails _try_rc assert_not_contains "hello world" "world"
    assert_fails _try_rc assert_contains "hello world" "PWNED"
    assert_contains "$(_try assert_not_contains "hello world" "world")" "expected NOT to find"
    assert_contains "$(_try assert_contains "hello world" "PWNED")" "expected to find"
}

#[test]
it_fails_every_other_assertion_when_it_should() {
    # The same control over the rest of the surface, because an assertion that
    # cannot fail is the one defect none of the suites using it would notice.
    assert_fails _try_rc assert_eq "a" "b"
    assert_fails _try_rc assert_ne "a" "a"
    assert_fails _try_rc assert_empty "not empty"
    assert_fails _try_rc assert_ok false
    assert_fails _try_rc assert_fails true
}

#[test]
it_passes_every_assertion_when_it_should() {
    # And the positive half, so the block above is not passing because
    # everything refuses.
    assert_ok _try_rc assert_eq "a" "a"
    assert_ok _try_rc assert_ne "a" "b"
    assert_ok _try_rc assert_empty ""
    assert_ok _try_rc assert_ok true
    assert_ok _try_rc assert_fails false
    assert_ok _try_rc assert_contains "hello" "ell"
    assert_ok _try_rc assert_not_contains "hello" "xyz"
}

#[test]
it_says_when_a_test_asserted_nothing() {
    # The guard that caught the missing assertion. A test body that checks
    # nothing is a test that cannot fail, and reporting it as a pass is how a
    # suite comes to mean nothing.
    local out
    out="$(cd "$NUTSHELL_ROOT" 2>/dev/null || cd .; ./test tests/fixtures/asserts_nothing_test.sh 2>&1)"
    assert_contains "$out" "asserted nothing"
}
