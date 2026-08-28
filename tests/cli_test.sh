#!/usr/bin/env bash
# Tests for subcommand dispatch.

use cli test

setup() {
    # Through the container API. It reset with bash array syntax, which after
    # the conversion assigned an empty string to three names that are now a
    # list and two maps, so it silently stopped resetting anything. The tests
    # still passed, because registering the same two commands twice is deduped
    # now, which is exactly the kind of pass that means nothing.
    list_new _CLI_ORDER
    map_new _CLI_SUMMARY
    map_new _CLI_HANDLER
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

#[test]
it_resets_between_setups() {
    # The property the old reset stopped having. Without it every test in this
    # file inherits whatever the last one registered, and a test that checks
    # what is listed cannot mean anything.
    setup
    cli_command "extra" "only here" handler_check
    assert_contains "$(cli_run help)" "extra"
    setup
    assert_not_contains "$(cli_run help)" "extra"
    assert_contains "$(cli_run help)" "build"
}

#[test]
it_keeps_one_entry_when_a_command_is_registered_twice() {
    # The second registration wins the dispatch, and the help lists the command
    # once. Before, the order list took the name twice and the help printed a
    # duplicate row while the second handler ran.
    setup
    cli_command "build" "compile it again" handler_check
    local out; out="$(cli_run help)"
    assert_eq "$(printf '%s\n' "$out" | grep -c '^  build ')" "1"
    assert_contains "$out" "compile it again"
    assert_eq "$(cli_run build)" "checked"
}

#[test]
it_takes_a_command_name_that_is_not_a_variable_name() {
    # Command names are map keys and go through the map's encoding, so a dash
    # or a dot is a key like any other. A tool with `foo-bar` subcommands is
    # the normal case rather than an exotic one.
    setup
    cli_command "git-lfs" "hyphenated" handler_check
    cli_command "a.b" "dotted" handler_build
    assert_eq "$(cli_run git-lfs)" "checked"
    assert_eq "$(cli_run a.b x)" "built:x"
    local out; out="$(cli_run help)"
    assert_contains "$out" "git-lfs"
    assert_contains "$out" "a.b"
    # And the two do not collide, which is what the encoding is for.
    assert_contains "$out" "hyphenated"
    assert_contains "$out" "dotted"
}

#[test]
it_pads_the_column_to_the_longest_name() {
    # The width goes into the format string because POSIX `printf` has no `*`
    # field width. A width that stopped being applied would leave the summaries
    # unaligned, which nothing else here would notice.
    setup
    cli_command "a" "short" handler_check
    cli_command "a-very-long-command" "long" handler_check
    local out; out="$(cli_run help)"
    # Both summaries start at the same column.
    local c1 c2
    c1="$(printf '%s\n' "$out" | grep '^  a  *short' | head -1)"
    c2="$(printf '%s\n' "$out" | grep '^  a-very-long-command  *long' | head -1)"
    assert_ne "$c1" ""
    assert_ne "$c2" ""
    # The column the summary starts at, which is the length of what precedes
    # it. Two earlier versions of this assertion were wrong rather than the
    # padding: comparing whole line lengths fails because the summaries differ
    # in length, and comparing the prefixes as strings fails because each holds
    # its own command name. Stripped from the end, since `%%long*` would cut at
    # the `long` inside `a-very-long-command`.
    local p1="${c1%short}" p2="${c2%long}"
    assert_eq "${#p1}" "${#p2}" "both summaries start at the same column"
}
