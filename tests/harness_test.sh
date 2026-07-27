#!/usr/bin/env bash
# Tests for the test harness itself.
#
# Run through a child process rather than a subshell. Bash suppresses errexit
# inside anything on the left of `||` or in an `if` condition, and the
# suppression reaches into subshells that set it themselves, so a test written
# as `( set -e; ... ) || rc=$?` observes the opposite of what it means to. A
# separate process has its own exit status and nothing to suppress.

use test

FIXTURES="${BASH_SOURCE[0]%/*}/fixtures"

# _harness_run <file> -> the harness's own output for that file
_harness_run() {
    # Through test_summary as well, so the child tidies up after itself the way
    # a real run does.
    bash -c '. "$1"/init; use test; test_run "$2"; test_summary' \
        _ "$NUTSHELL_ROOT" "$1" 2>&1
}

#[test]
it_fails_a_test_whose_first_assertion_failed() {
    # A function's exit status is its last command's, so a test with several
    # assertions used to report only the final one: the first three could fail
    # with the run still green. That is not a weak test but a test that cannot
    # fail, and it was hiding a real defect in the graph cache.
    local out
    out="$(_harness_run "${FIXTURES}/first_assertion_fails_test.sh")"
    assert_contains "$out" "FAIL"
}

#[test]
it_names_the_failing_test_on_the_failure_line() {
    # Both halves on one line. Asserting only that the name appears somewhere
    # proves nothing: the name appears on a passing line too.
    local out
    out="$(_harness_run "${FIXTURES}/first_assertion_fails_test.sh")"
    assert_contains "$out" "[FAIL] it_should_be_reported_as_a_failure"
}

#[test]
it_shows_the_values_that_did_not_match() {
    # A bare "assertion failed" sends the reader back to the source to work out
    # what the values even were, and the values are the whole content.
    local out
    out="$(_harness_run "${FIXTURES}/first_assertion_fails_test.sh")"
    assert_contains "$out" "expected [b]"
    assert_contains "$out" "got [a]"
}
