#!/usr/bin/env bash
# Tests for the cruft check saying which file it refused.
#
# `./check` shows a failing check's `✗` lines and drops everything else, so the
# cyan filename header the check prints above each group never reaches the
# reader. What reached them was `✗ Line 165: Comment contains 'compatibility
# shim'`, a line number with no file, and finding the file took three greps
# over the tree.
#
# The arms drive `test_no_cruft` over a planted tree rather than over this
# repository, so what they assert is the message rather than whatever the
# repository happens to hold today.

use test

NUT_CHECK_LOAD_ONLY=1 . "${BASH_SOURCE[0]%/*}/../examples/checks/check_no_cruft.sh"

_nc_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-nocruft.XXXXXX")"
trap '[[ -n "${_nc_TMP:-}" ]] && rm -rf "$_nc_TMP"' EXIT

# A tree holding one file, scanned as the whole project. `get_script_files` is
# the check's only way of asking what to read, so overriding it is what bounds
# the run to the plant.
_nc_scan() { # <file body> -> the check's output
    local body="$1"
    local d="$_nc_TMP/one"
    rm -rf "$d"; mkdir -p "$d/lib"
    printf '%s\n' "$body" > "$d/lib/planted.sh"

    (
        REPO_ROOT="$d"
        FAIL_ON_DEBUG=true
        FAIL_ON_TODO=true
        MAX_TODOS=0
        # `load_config` reads the project's `nut.toml` and is what fills these.
        # Set here instead, so an arm reports on what it planted rather than on
        # whatever a config elsewhere happens to say.
        DEBUG_PATTERNS=("echo.*DEBUG" "set -x")
        TODO_PATTERNS=("TODO:" "FIXME:")
        get_script_files() { printf '%s\n' "$REPO_ROOT/lib/planted.sh"; }
        test_no_cruft 2>&1
    )
}

#[test]
it_names_the_file_a_comment_was_refused_in() {
    local out; out="$(_nc_scan '# a compat shim for the old callers')"
    assert_contains "$out" "lib/planted.sh:1:"
}

#[test]
it_names_the_file_a_flagged_function_is_in() {
    local out; out="$(_nc_scan 'thing_deprecated() { :; }')"
    assert_contains "$out" "lib/planted.sh:1:"
}

#[test]
it_names_the_file_a_flagged_variable_is_in() {
    # `THING_DEPRECATED` rather than `OLD_THING`, because the variable pattern
    # carries `_OLD$` and `^OLD_` inside an alternation in the middle of the
    # regex, where an anchor matches nothing, so neither of those two ever
    # fires. Tracked as `the-cruft-checks-name-patterns-carry-dead-anchors`.
    local out; out="$(_nc_scan 'THING_DEPRECATED=1')"
    assert_contains "$out" "lib/planted.sh:1:"
}

#[test]
it_names_the_file_a_todo_is_in() {
    local out; out="$(_nc_scan '# TODO: take this out')"
    assert_contains "$out" "lib/planted.sh:1:"
}

#[test]
it_keeps_the_line_number_it_always_had() {
    # The path is added beside the line number, not instead of it.
    local out; out="$(_nc_scan 'ok=1
# a compat shim for the old callers')"
    assert_contains "$out" "lib/planted.sh:2:"
}

#[test]
it_says_nothing_about_a_file_holding_no_cruft() {
    # The control. A check naming a file on every run would satisfy every arm
    # above and find nothing.
    local out; out="$(_nc_scan 'ok=1
# an ordinary comment about ordinary work')"
    assert_fails grep -q 'lib/planted.sh:' <<<"$out"
}
