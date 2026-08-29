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

#[test]
# What the verdict says when a test stops without reaching its end.
#
# It said only "the test did not finish", which is not diagnosable, and this
# repo has an intermittent failure of exactly that shape: four tests in
# `deps_test.sh` that fail together under a full suite run and pass when run on
# their own. Twice now, with no more to go on than that sentence.
#
# The tally distinguishes two different faults. Empty means the body never
# reached its first assertion; a partial one means it stopped part way and says
# how far it got. A missing marker file is a third thing again and is about the
# harness rather than the test.
it_says_how_far_a_test_got_before_it_stopped() {
    local d; d="$(mktemp -d)"
    # The attribute is assembled rather than written. Discovery greps the
    # source for `#[test]`, and it does not know a heredoc from code: written
    # literally here, the probe's function is registered as a test of *this*
    # file, where it does not exist, and the run reports a command not found.
    {
        printf 'use test\n'
        printf '#%s\n' '[test]'
        printf 'it_dies_after_one_assertion() {\n'
        printf '    assert_eq 1 1\n'
        printf '    exit 3\n'
        printf '}\n'
    } > "$d/zz_probe_test.sh"
    # The nested run gets a clean environment. `_TEST_MARK_DIR` and
    # `_TEST_MARK` are exported, so a child harness writes its markers into the
    # parent's directory and the parent then reads the child's tests as its
    # own: the first version of this test reported the probe's deliberate
    # failure as a failure of this file.
    local out
    out="$(env -u _TEST_MARK_DIR -u _TEST_MARK -u TEST_FILTER \
        "${NUTSHELL_ROOT}/test" "$d/zz_probe_test.sh" 2>&1)"
    rm -rf "$d"

    assert_contains "$out" "did not finish"
    # The part that was missing: which state it was in.
    assert_contains "$out" "stopped part way"
    assert_contains "$out" "'a'"
}

#[test]
# The pass and fail counters are numbers, not strings.
#
# They were `declare -gi`, and dropping that attribute during the floor work
# turned `_TEST_PASSED+=1` from addition into concatenation: six passing tests
# reported as `0111111 passed`. The suite still said OK, so nothing failed and
# every number the harness printed was nonsense.
#
# Asserted through a nested run, because the counters belong to the run that
# owns them and this one is inside a run of its own.
it_counts_passes_as_a_number() {
    local d; d="$(mktemp -d)"
    {
        printf 'use test\n'
        printf '#%s\n' '[test]'
        printf 'it_one() { assert_eq 1 1; }\n'
        printf '#%s\n' '[test]'
        printf 'it_two() { assert_eq 2 2; }\n'
        printf '#%s\n' '[test]'
        printf 'it_three() { assert_eq 3 3; }\n'
    } > "$d/zz_count_test.sh"

    local out
    out="$(env -u _TEST_MARK_DIR -u _TEST_MARK -u TEST_FILTER \
        "${NUTSHELL_ROOT}/test" "$d/zz_count_test.sh" 2>&1)"
    rm -rf "$d"

    # Three, not `0111`.
    assert_contains "$out" "3 passed"
    assert_not_contains "$out" "0111"
}

#[test]
it_fails_a_test_whose_assertion_name_was_misspelled() {
    # `assert_fail` for `assert_fails` printed `command not found` to stderr,
    # added nothing to the tally, and the test passed on its other assertions.
    # Nobody reads the stderr of a passing test, so the assertion that did
    # nothing was invisible in exactly the tests that had the most of them,
    # and only a test where every assertion was misspelled got caught.
    local d; d="$(mktemp -d)"
    # Attribute assembled rather than written, per the note above: discovery
    # greps the source and does not know a heredoc from code.
    {
        printf 'use test\n'
        printf '#%s\n' '[test]'
        printf 'it_has_one_good_and_one_misspelled() {\n'
        printf '    assert_eq "a" "a"\n'
        printf '    assert_fail true\n'
        printf '}\n'
    } > "$d/zz_typo_test.sh"
    local out
    out="$(env -u _TEST_MARK_DIR -u _TEST_MARK -u TEST_FILTER \
        "${NUTSHELL_ROOT}/test" "$d/zz_typo_test.sh" 2>&1)" || true
    rm -rf "$d"
    assert_contains "$out" "assertion name was not found"
}

#[test]
it_does_not_fail_a_test_for_a_missing_command_that_is_not_an_assertion() {
    # The control. A test may legitimately run something that is not
    # installed and check what happens, so the guard matches the `assert_`
    # stem rather than `command not found` on its own.
    local d; d="$(mktemp -d)"
    {
        printf 'use test\n'
        printf '#%s\n' '[test]'
        printf 'it_runs_a_command_that_is_absent() {\n'
        printf '    definitely_not_a_real_command_here 2>/dev/null || true\n'
        printf '    assert_eq "a" "a"\n'
        printf '}\n'
    } > "$d/zz_absent_test.sh"
    local out
    out="$(env -u _TEST_MARK_DIR -u _TEST_MARK -u TEST_FILTER \
        "${NUTSHELL_ROOT}/test" "$d/zz_absent_test.sh" 2>&1)" || true
    rm -rf "$d"
    assert_contains "$out" "1 passed"
    assert_not_contains "$out" "assertion name was not found"
}

#[test]
it_does_not_fail_a_test_that_prints_assert_and_separately_runs_a_missing_command() {
    # The first version of the guard matched `assert_` and `command not found`
    # anywhere in the whole output, so the two halves could come from unrelated
    # lines and an honest test failed with a verdict that was a lie about it.
    # This file is full of that shape: it builds test sources containing
    # `assert_eq` and captures the runner's output.
    local d; d="$(mktemp -d)"
    {
        printf 'use test\n'
        printf '#%s\n' '[test]'
        printf 'it_prints_a_snippet_then_runs_a_missing_tool() {\n'
        printf '    printf %s\n' "'the source reads: assert_eq \"a\" \"a\"\\n'"
        printf '    definitely_not_a_real_tool_xyz\n'
        printf '    assert_eq "a" "a"\n'
        printf '}\n'
    } > "$d/zz_blob_test.sh"
    local out
    out="$(env -u _TEST_MARK_DIR -u _TEST_MARK -u TEST_FILTER \
        "${NUTSHELL_ROOT}/test" "$d/zz_blob_test.sh" 2>&1)" || true
    rm -rf "$d"
    assert_contains "$out" "1 passed"
    assert_not_contains "$out" "assertion name was not found"
}

#[test]
# A file that will not source used to look like every test in it dying at once,
# with no hint of why.
#
# The runner sources the file again per test, in the subshell where the function
# has to end up, and that source's output went to /dev/null. When it failed the
# function was never defined, calling it did nothing, the closing mark never
# ran, and every test in the file came back "marker empty" at 0.0s. A whole
# file of ninety failed that way one night and the same file passed ninety for
# ninety twenty minutes later, and there was no way to tell what had been
# different.
it_says_what_the_file_wrote_when_it_would_not_source() {
    local d; d="$(mktemp -d)"
    {
        printf 'use test\n'
        printf '#%s\n' '[test]'
        printf 'it_never_gets_to_run() {\n'
        printf '    assert_eq 1 1\n'
        printf '}\n'
        # After the function, so discovery still finds it and the source still
        # dies. A file that failed before the definition would be a different
        # and much more obvious fault.
        printf 'printf "the reason it broke\\n" >&2\n'
        printf 'return 7\n'
    } > "$d/zz_badsrc_test.sh"

    local out
    out="$(env -u _TEST_MARK_DIR -u _TEST_MARK -u TEST_FILTER \
        "${NUTSHELL_ROOT}/test" "$d/zz_badsrc_test.sh" 2>&1)"
    rm -rf "$d"

    assert_contains "$out" "did not finish"
    # The whole point: what the file said on its way down.
    assert_contains "$out" "the reason it broke"
    # And not the old message, which was the symptom of every cause at once.
    assert_not_contains "$out" "marker empty"
}

#[test]
# The other half: the file sources cleanly but defines nothing by that name.
#
# Discovery greps for the attribute, so a function renamed under its own marker
# is registered and then not there. That reads identically to a test that died,
# and it is a different fault with a different fix.
it_says_so_when_the_file_defines_no_such_test() {
    local d; d="$(mktemp -d)"
    {
        printf 'use test\n'
        printf '#%s\n' '[test]'
        printf 'it_was_renamed_and_the_marker_left_behind() {\n'
        printf '    assert_eq 1 1\n'
        printf '}\n'
        # Removed again, which is what a rename leaves behind.
        printf 'unset -f it_was_renamed_and_the_marker_left_behind\n'
    } > "$d/zz_gone_test.sh"

    local out
    out="$(env -u _TEST_MARK_DIR -u _TEST_MARK -u TEST_FILTER \
        "${NUTSHELL_ROOT}/test" "$d/zz_gone_test.sh" 2>&1)"
    rm -rf "$d"

    assert_contains "$out" "defines no it_was_renamed_and_the_marker_left_behind"
}

#[test]
# The control for both of the above. A file that sources fine and defines what
# it says still passes, so the new branches cannot be swallowing good runs.
it_still_runs_a_file_that_sources_cleanly() {
    local d; d="$(mktemp -d)"
    {
        printf 'use test\n'
        printf '#%s\n' '[test]'
        printf 'it_is_perfectly_fine() {\n'
        printf '    assert_eq 1 1\n'
        printf '}\n'
    } > "$d/zz_fine_test.sh"

    local out
    out="$(env -u _TEST_MARK_DIR -u _TEST_MARK -u TEST_FILTER \
        "${NUTSHELL_ROOT}/test" "$d/zz_fine_test.sh" 2>&1)"
    rm -rf "$d"

    assert_contains     "$out" "1 passed"
    assert_not_contains "$out" "did not finish"
}
