#!/usr/bin/env bash
# Tests for subcommand dispatch.

use cli test

setup() {
    _CLI_ORDER=(); _CLI_SUMMARY=(); _CLI_HANDLER=()
    cli_name "demo"
    cli_command "build" "compile it" handler_build
    cli_command "check" "verify it"  handler_check
}
handler_build() { echo "built:$*"; }
handler_check() { echo "checked"; }

#[test]
it_dispatches_to_the_handler() {
    setup
    assert_eq "$(cli_run build --fast)" "built:--fast"
}

#[test]
it_lists_every_command_in_the_usage() {
    setup
    local out; out="$(cli_run help)"
    assert_contains "$out" "build"
    assert_contains "$out" "check"
}

#[test]
it_suggests_the_nearest_command() {
    setup
    assert_eq "$(cli_nearest buld)" "build"
}

#[test]
it_suggests_nothing_for_an_unrelated_word() {
    # The threshold has to refuse as well as accept, or every typo gets a
    # confident wrong answer.
    setup
    assert_empty "$(cli_nearest zzzzzz)"
}

#[test]
it_fails_with_a_usage_code_on_an_unknown_command() {
    setup
    # EX_USAGE. The code, not merely non-zero: a command that refuses because
    # it crashed is a different bug from one that refuses because it did not
    # recognise the word.
    assert_exits 64 cli_run nonsense >/dev/null 2>&1
}
