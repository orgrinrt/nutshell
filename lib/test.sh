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

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded: under a POSIX shell `nut_once` is not found, the `|| return
# 0` returns from the whole file, and the module then defines nothing while
# reporting success.
[ -n "${_NUTSHELL_TEST_SH:-}" ] && return 0
_NUTSHELL_TEST_SH=1

# A newline as itself. There is no `$'\n'` here to write one inline with, and
# the trailing `.` is because command substitution strips the trailing newline,
# which is the character being asked for.
_TEST_NL="$(printf '\n.')"; _TEST_NL="${_TEST_NL%.}"

use attr log fs list

_TEST_PASSED=0
_TEST_FAILED=0
# A `list` rather than an indexed array, which is bash's. It only ever grows by
# one and is read once at the end, which is what `list` is for.
list_new _TEST_FAILURES

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
    _test_mark f
    return 1
}

# _test_mark <a|f|z>
#
# One character on the tally: `a` an assertion was evaluated, `f` one failed,
# `z` the body returned rather than dying part way through.
#
# A file, because each test runs in its own subshell and a variable set there
# cannot reach the runner that has to decide the verdict.
_test_mark() {
    [ -n "${_TEST_MARK:-}" ] && printf '%s' "$1" >> "$_TEST_MARK"
    return 0
}

# _test_asserted -> record that an assertion happened, whatever its outcome
_test_asserted() { _test_mark a; }

#[pub]
# Usage: assert_eq "$got" "$want" ["what this is about"] -> 0 or 1
assert_eq() {
    _test_asserted
    [ "$1" = "$2" ] && return 0
    _test_failed "expected [$2]" "     got [$1]" ${3:+"     $3"}
}

#[pub]
# Usage: assert_ne "$got" "$unwanted" ["what this is about"] -> 0 or 1
assert_ne() {
    _test_asserted
    [ "$1" != "$2" ] && return 0
    _test_failed "expected anything but [$2]" ${3:+"     $3"}
}

#[pub]
# Usage: assert_contains "$haystack" "$needle" ["about"] -> 0 or 1
assert_contains() {
    _test_asserted
    case "$1" in *"$2"*) return 0 ;; esac
    _test_failed "expected to find [$2]" "            in [$1]" ${3:+"     $3"}
}

#[pub]
# The negation, which was missing and cost three tests.
#
# Without it, `assert_not_contains` is an unknown command: it prints to stderr,
# it does not register an assertion, and the test around it passes on whatever
# else it happened to check. Three tests in this repo carried a line that did
# nothing, and two of them reported a pass. The harness's own
# "asserted nothing" guard caught the third, which is the only reason any of
# them were found.
#
# Usage: assert_not_contains "$output" "PWNED"
assert_not_contains() {
    _test_asserted
    case "$1" in *"$2"*) ;; *) return 0 ;; esac
    _test_failed "expected NOT to find [$2]" "                in [$1]" ${3:+"     $3"}
}

#[pub]
# Usage: assert_empty "$value" ["about"] -> 0 or 1
assert_empty() {
    _test_asserted
    [ -z "$1" ] && return 0
    _test_failed "expected nothing, got [$1]" ${2:+"     $2"}
}

#[pub]
# Usage: assert_ok some_command args -> 0 when it succeeds
assert_ok() {
    _test_asserted
    local rc=0
    "$@" || rc=$?
    [ "$rc" -eq 0 ] && return 0
    _test_failed "expected success from [$*], got exit ${rc}"
}

#[pub]
# Usage: assert_fails some_command args -> 0 when it fails
#
# For the cases worth pinning most: a guard that must refuse. A function that
# quietly started succeeding where it used to refuse is the change nobody
# notices without this.
assert_fails() {
    _test_asserted
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
    _test_asserted
    local want="$1"; shift
    local rc=0
    "$@" || rc=$?
    [ "$rc" -eq "$want" ] && return 0
    _test_failed "expected exit [${want}] from [$*]" "     got exit [${rc}]"
}

# -----------------------------------------------------------------------------
# Running
# -----------------------------------------------------------------------------

# _test_now_us -> the time in whole microseconds, or nothing
#
# EPOCHREALTIME spells its decimal separator per locale, so feeding it to awk
# under a comma locale truncated at the comma and every tenth printed as zero.
# Whether a test's output holds the shell complaining about a missing
# assertion, which is what a misspelled assertion name leaves behind.
#
# Line by line, and this is the whole reason it is a function. Matched against
# the output as one blob, the two halves come from different lines: a test that
# prints the text `assert_eq` and separately runs some command that is not
# installed satisfies `*assert_*command not found*` between them and fails with
# a verdict that is a lie about it. This file's own tests build sources
# containing `assert_eq` and capture the runner's output, four times over, so
# that is not a hypothetical shape here.
#
# The `: ` before the name is the rest of it. The shell says
# `file: line 5: assert_fail: command not found`, so the name is preceded by a
# colon and a space, and requiring those stops a line merely *mentioning*
# `assert_` before an unrelated complaint from matching.
_test_has_missing_assertion() {
    # The answer comes back as output rather than as a status. The loop runs in
    # the pipeline's subshell, so a `return` inside it returns from nothing and
    # the pipeline reports success whether the line was found or not.
    _tha_found="$(printf '%s\n' "${1:-}" | while IFS= read -r _tha_line; do
        case "$_tha_line" in
            *": assert_"*": command not found"*) printf 'y'; break ;;
        esac
    done)"
    [ "$_tha_found" = "y" ]
}

# The digits alone are seconds followed by exactly six digits of microseconds,
# so stripping the separator leaves an integer that subtracts cleanly. Empty
# under bash older than 5.0, and the caller then prints no timing rather than
# a wrong one.
_test_now_us() {
    local t="${EPOCHREALTIME:-}" out="" run
    [ -n "$t" ] || return 0
    # Digits only, `1234.5678` to `12345678`. Walked rather than
    # `${t//[!0-9]/}`, which is bash's; whole digit runs are taken at once, so
    # this is two passes rather than one per character.
    #
    # `EPOCHREALTIME` is bash's too, so on the floor `$t` is empty and this
    # returns nothing, which is the fallback the caller already handles by
    # printing no timing rather than a wrong one.
    while [ -n "$t" ]; do
        run="${t%%[!0-9]*}"
        if [ -n "$run" ]; then
            out="${out}${run}"; t="${t#"$run"}"; continue
        fi
        t="${t#?}"
    done
    printf '%s' "$out"
}

# _test_mark_dir -> a directory to keep one tally per test in
#
# One file per test, not one file truncated between them. The shared file was
# smaller and it was wrong: a test that forks leaves a child able to write to
# the tally after the runner has moved on, and the failure was charged to
# whichever test came next. The guilty one passed and an innocent one failed.
#
# A directory is still one thing to remove at the end.
_test_mark_dir() {
    [ -n "${_TEST_MARK_DIR:-}" ] && { printf '%s' "$_TEST_MARK_DIR"; return 0; }
    fs_temp_dir nutshell-test
}

#[pub]
# Usage: test_run tests/string_test.sh -> runs every #[test] in the file
test_run() {
    local file="$1"
    [ -f "$file" ] || { log_error "no test file: ${file}"; return 1; }

    local name output rc
    _TEST_MARK_DIR="$(_test_mark_dir)" || return 1

    # A file that yields no tests at all, counted before any filter. The same
    # reasoning as the assert-nothing check below, one level up: a file nobody
    # can run occupies the place a real one would be noticed missing from, and
    # `[OK] 0 passed` reads as a pass.
    #
    # It is not hypothetical. Renaming `attr_find` breaks the discovery this
    # very loop uses, so every file in the suite yields nothing and the run
    # reports green over a library that no longer loads.
    local found=0 _tf_names
    # Gathered first. The body counts into `found`, which the code after it
    # reads, so on the right of a pipe the count would be made in a subshell
    # and read back as zero here: every file would report no tests.
    _tf_names="$(attr_find "$file" test)"
    while IFS= read -r name; do
        [ -n "$name" ] && found=$(( found + 1 ))
    done <<EOF
$_tf_names
EOF

    if [ "$found" -eq 0 ]; then
        _TEST_FAILED=$(( _TEST_FAILED + 1 ))
        list_push _TEST_FAILURES "${file##*/}: no #[test] found in the file"
        log_tagged "FAIL" red "${file##*/}"
        log_substep "no #[test] found. An empty file reports a pass otherwise."
        return 1
    fi

    # Same here-document, same reason: the body counts passes and failures
    # into variables the summary reads.
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        if [ -n "${TEST_FILTER:-}" ]; then
            case "$name" in *"$TEST_FILTER"*) ;; *) continue ;; esac
        fi

        # Its own file, so nothing a previous test left behind, and nothing a
        # previous test is still doing, can be read as this one's.
        _TEST_MARK="${_TEST_MARK_DIR}/$(( _TEST_PASSED + _TEST_FAILED )).${name}"
        : > "$_TEST_MARK"

        # A subshell per test. Bash has one global namespace, so without this a
        # test that sets a variable or cd's changes what the next one sees, and
        # the failure surfaces in the innocent test rather than the guilty one.
        # `_test_mark z` after the call, so a body that returned is told apart
        # from one that died part way through. It runs whatever the function's
        # status, because a test is allowed to end on a command that returns
        # non-zero and half this library returns non-zero on purpose.
        local start_us end_us took=""
        start_us="$(_test_now_us)"
        output="$( set +e; . "$file" >/dev/null 2>&1; "$name" 2>&1; _test_mark z )"
        end_us="$(_test_now_us)"
        [ -n "$start_us" ] && [ -n "$end_us" ] &&
            took=" ($(( (end_us - start_us) / 1000000 )).$(( (end_us - start_us) / 100000 % 10 ))s)"

        # The tally decides, not the exit status. A test whose last command
        # happened to return non-zero used to fail with every assertion in it
        # passing, which contradicted the note above and made the verdict
        # depend on which line a test ended with.
        local tally why=""
        tally="$(cat "$_TEST_MARK" 2>/dev/null)"
        rc=0
        local _has_z=0; case "$tally" in *z*) _has_z=1 ;; esac
        if [ "$_has_z" -eq 0 ]; then
            # What the marker actually held, because "did not finish" alone is
            # not diagnosable and this has fired intermittently on tests that
            # pass when run on their own. An empty tally and a truncated one
            # are different faults: empty says the test body never reached its
            # first mark, and a partial one says it stopped part way.
            rc=1
            if [ ! -e "$_TEST_MARK" ]; then
                why="the test did not finish (its marker file is gone: ${_TEST_MARK})"
            elif [ -z "$tally" ]; then
                why="the test did not finish (marker empty, so it stopped before the first assertion)"
            else
                why="the test did not finish (marker held '${tally}', so it stopped part way)"
            fi
        elif case "$tally" in *f*) true ;; *) false ;; esac; then
            rc=1
        elif case "$tally" in *a*) false ;; *) true ;; esac; then
            # Worse than a weak test: it occupies the place a real one would be
            # noticed missing from, and it counts toward a number people quote.
            rc=1; why="the test asserted nothing"
        elif _test_has_missing_assertion "$output"; then
            # A misspelled assertion name. The shell says so on stderr and
            # carries on, the tally never hears about it, and the test passes
            # on whatever other assertions it happened to have. Only a test
            # where every assertion was misspelled was caught, by the guard
            # above, which is the worst way round: the more a test asserts, the
            # better it hides one that does nothing.
            #
            # It reads stderr, so it is a good check rather than a complete
            # one: `{ assert_fail true; } 2>/dev/null` is invisible to it. The
            # deterministic answer is `command_not_found_handle`, which fires
            # inside the test and cannot be redirected away, and which this
            # file cannot use while it runs on the POSIX floor.
            rc=1; why="an assertion name was not found, so it asserted nothing"
        fi
        [ -n "$why" ] && output="${output}${output:+$_TEST_NL}${why}"

        if [ $rc -eq 0 ]; then
            _TEST_PASSED=$(( _TEST_PASSED + 1 ))
            log_tagged "PASS" green "$name${took}"
        else
            _TEST_FAILED=$(( _TEST_FAILED + 1 ))
            list_push _TEST_FAILURES "${file##*/}: ${name}"
            log_tagged "FAIL" red "$name${took}"
            [ -n "$output" ] && printf '%s\n' "$output" | while IFS= read -r l; do
                log_substep "$l"
            done
        fi
    done <<EOF
$_tf_names
EOF
}

#[pub]
# Usage: test_run_dir tests -> runs every *_test.sh under the directory
test_run_dir() {
    local dir="${1:-tests}" file
    for file in "$dir"/*_test.sh; do
        [ -f "$file" ] || continue
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
    [ -n "${_TEST_MARK_DIR:-}" ] && rm -rf "$_TEST_MARK_DIR"
    printf '\n'
    if [ "$_TEST_FAILED" -gt 0 ]; then
        local f _tf_i=0 _tf_n
        _tf_n="$(list_len _TEST_FAILURES)"
        while [ "$_tf_i" -lt "$_tf_n" ]; do
            list_read f _TEST_FAILURES "$_tf_i"
            log_tagged "FAILED" red "$f"
            _tf_i=$(( _tf_i + 1 ))
        done
        log_error "${_TEST_FAILED} failed, ${_TEST_PASSED} passed"
        return 1
    fi
    log_success "${_TEST_PASSED} passed"
    return 0
}
