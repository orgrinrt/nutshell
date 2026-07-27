#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/test.sh - Tests, found by attribute
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 1: uses attr and log.
#
#   #[test]
#   it_trims_both_ends() {
#       assert_eq "$(str_trim "  x  ")" "x"
#   }
#
# A test is a function marked `#[test]`. Nothing registers it, nothing lists it
# in a table beside itself, and there is no naming convention to remember: the
# marker is the registration, so a test that exists cannot be missing from the
# run and a name that changes cannot leave a stale entry behind.
#
# Each test runs in a subshell. A test that sets a global, changes directory or
# defines a function cannot reach the next one, which matters more here than in
# most languages because bash has one global namespace and no other isolation
# to offer.
#
# Failures do not stop the run. Knowing that four things broke, and which four,
# beats knowing that the first one did.
#
# Usage:
#   use test
#
#   test_run tests/string_test.sh       # one file
#   test_summary                        # totals; returns 1 if anything failed
#
# Environment:
#   TEST_FILTER - only run tests whose name contains this
# =============================================================================

nut_once || return 0

use attr log fs

declare -gi _TEST_PASSED=0
declare -gi _TEST_FAILED=0
declare -ga _TEST_FAILURES=()

# -----------------------------------------------------------------------------
# Assertions
# -----------------------------------------------------------------------------
#
# Each prints what it expected against what it got, because a bare "assertion
# failed" sends the reader back to the source to work out what the values even
# were, and the values are the whole content of the failure.
#
# Every failure is recorded, not merely returned. A bash function's exit status
# is its last command's, so a test with four assertions used to report only the
# fourth: the first three could fail with the run still green. That is not a
# weak test but a test that cannot fail, and it was hiding a real defect in the
# graph cache.
#
# The obvious fix, running the test body under `set -e`, is wrong here. errexit
# reaches into every function the test calls, so a test could no longer call
# anything that returns non-zero on purpose, and half this library does:
# `modgraph_audit` returns 1 when it finds violations, and a test asking what it
# found would die before asking. A mark on the side counts every assertion and
# leaves the body's control flow alone.

# _test_failed <line...>
#
# Report a failed assertion and record that one happened. The record is a file
# because each test runs in its own subshell, and a variable set there cannot
# reach the runner that has to decide the verdict.
_test_failed() {
    printf '%s\n' "$@" >&2
    [[ -n "${_TEST_MARK:-}" ]] && printf 'x' >> "$_TEST_MARK"
    return 1
}

#[pub]
# Usage: assert_eq "$got" "$want" ["what this is about"] -> 0 or 1
assert_eq() {
    [[ "$1" == "$2" ]] && return 0
    _test_failed "expected [$2]" "     got [$1]" ${3:+"     $3"}
}

#[pub]
# Usage: assert_ne "$got" "$unwanted" ["what this is about"] -> 0 or 1
assert_ne() {
    [[ "$1" != "$2" ]] && return 0
    _test_failed "expected anything but [$2]" ${3:+"     $3"}
}

#[pub]
# Usage: assert_contains "$haystack" "$needle" ["about"] -> 0 or 1
assert_contains() {
    [[ "$1" == *"$2"* ]] && return 0
    _test_failed "expected to find [$2]" "            in [$1]" ${3:+"     $3"}
}

#[pub]
# Usage: assert_empty "$value" ["about"] -> 0 or 1
assert_empty() {
    [[ -z "$1" ]] && return 0
    _test_failed "expected nothing, got [$1]" ${2:+"     $2"}
}

#[pub]
# Usage: assert_ok some_command args -> 0 when it succeeds
assert_ok() {
    local rc=0
    "$@" || rc=$?
    [[ "$rc" -eq 0 ]] && return 0
    _test_failed "expected success from [$*], got exit ${rc}"
}

#[pub]
# Usage: assert_fails some_command args -> 0 when it fails
#
# For the cases worth pinning most: a guard that must refuse. A function that
# quietly started succeeding where it used to refuse is the change nobody
# notices without this.
assert_fails() {
    if "$@"; then
        _test_failed "expected failure from [$*], got success"
        return 1
    fi
    return 0
}

#[pub]
# Usage: assert_exits 64 some_command args -> 0 when it exits with that code
#
# The status, not merely non-zero. A command that refuses for the wrong reason
# is a different bug from one that refuses for the right one, and a bare
# `assert_fails` cannot tell them apart.
assert_exits() {
    local want="$1"; shift
    local rc=0
    "$@" || rc=$?
    [[ "$rc" -eq "$want" ]] && return 0
    _test_failed "expected exit [${want}] from [$*]" "     got exit [${rc}]"
}

# -----------------------------------------------------------------------------
# Running
# -----------------------------------------------------------------------------

# _test_mark_file -> a path the subshells can append a failure to
#
# One file for the whole run, truncated between tests, rather than one per
# test: the runner has to clean up after itself either way, and a single path
# is one thing to remove rather than a list to keep.
_test_mark_file() {
    [[ -n "${_TEST_MARK:-}" ]] && { printf '%s' "$_TEST_MARK"; return 0; }
    fs_temp_file nutshell-test
}

#[pub]
# Usage: test_run tests/string_test.sh -> runs every #[test] in the file
test_run() {
    local file="$1"
    [[ -f "$file" ]] || { log_error "no test file: ${file}"; return 1; }

    local name output rc
    _TEST_MARK="$(_test_mark_file)" || return 1

    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        [[ -n "${TEST_FILTER:-}" && "$name" != *"$TEST_FILTER"* ]] && continue

        # Truncated per test, so one test's failures cannot be read as the
        # next one's.
        : > "$_TEST_MARK"

        # A subshell per test. Bash has one global namespace, so without this a
        # test that sets a variable or cd's changes what the next one sees, and
        # the failure surfaces in the innocent test rather than the guilty one.
        output="$( set +e; . "$file" >/dev/null 2>&1; "$name" 2>&1 )"
        rc=$?

        # Either signal is enough: a test that returned non-zero failed, and so
        # did one whose assertions failed before a later line returned zero.
        [[ -s "$_TEST_MARK" ]] && rc=1

        if [[ $rc -eq 0 ]]; then
            _TEST_PASSED+=1
            log_tagged "PASS" green "$name"
        else
            _TEST_FAILED+=1
            _TEST_FAILURES+=("${file##*/}: ${name}")
            log_tagged "FAIL" red "$name"
            [[ -n "$output" ]] && printf '%s\n' "$output" | while IFS= read -r l; do
                log_substep "$l"
            done
        fi
    done < <(attr_find "$file" test)
}

#[pub]
# Usage: test_run_dir tests -> runs every *_test.sh under the directory
test_run_dir() {
    local dir="${1:-tests}" file
    for file in "$dir"/*_test.sh; do
        [[ -f "$file" ]] || continue
        log_step "${file##*/}"
        test_run "$file"
    done
}

#[pub]
# Usage: test_summary -> prints totals, returns 1 if anything failed
#
# Also the end of the run, so the mark file goes here. A trap would fire on
# every subshell exit as well, and there is exactly one place the run is over.
test_summary() {
    [[ -n "${_TEST_MARK:-}" ]] && rm -f "$_TEST_MARK"
    printf '\n'
    if [[ "$_TEST_FAILED" -gt 0 ]]; then
        local f
        for f in "${_TEST_FAILURES[@]}"; do
            log_tagged "FAILED" red "$f"
        done
        log_error "${_TEST_FAILED} failed, ${_TEST_PASSED} passed"
        return 1
    fi
    log_success "${_TEST_PASSED} passed"
    return 0
}
