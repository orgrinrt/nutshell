#!/usr/bin/env bash
# Tests for tool detection.

use deps test

#[test]
it_finds_a_tool_from_the_eager_list() {
    assert_ok deps_has sed
}

#[test]
it_finds_a_tool_outside_the_eager_list() {
    # init scans a fixed set of unix text tools. Everything else answered "no",
    # whatever the machine had, so `json.sh` fell past jq and python to perl on
    # every machine and `http.sh` reported itself unavailable on all of them.
    # Both modules were right to ask; the answer was wrong.
    #
    # `env` rather than jq or curl: it is on every unix and it is not in the
    # eager list, so the test does not pass or fail on what happens to be
    # installed here.
    assert_ok deps_has env
}

#[test]
it_reports_where_a_lazily_found_tool_is() {
    # `deps_has` and `deps_path` used to disagree: asking whether a tool was
    # there found it, asking where it was did not, because only the first had
    # been taught to look.
    assert_contains "$(deps_path env)" "/env"
}

#[test]
it_refuses_a_tool_that_is_not_there() {
    assert_fails deps_has definitely_not_a_real_tool_xyzzy
}

#[test]
it_lists_a_lazily_found_tool_as_available() {
    # The list used to be readonly from the moment init finished, which froze
    # the answer rather than the source of truth.
    deps_has env
    assert_contains "$(deps_available)" "env"
}

#[test]
it_answers_the_same_way_through_every_door() {
    # `deps_has` was taught to look for a tool outside the eager list and its
    # siblings were not, so in a fresh shell `deps_has env` succeeded while
    # `deps_has_all env` failed and `deps_run env` reported it unavailable,
    # and all three flipped once anything had asked. An answer that depends on
    # what was asked earlier is worse than a wrong one.
    #
    # Each door in its own subshell, so none of them warms the table for the
    # next.
    assert_ok bash -c '. "$1"/init; use deps; deps_has_all env' _ "$NUTSHELL_ROOT"
    assert_ok bash -c '. "$1"/init; use deps; deps_has_any env' _ "$NUTSHELL_ROOT"
    assert_ok bash -c '. "$1"/init; use deps; deps_run env true' _ "$NUTSHELL_ROOT"
    assert_ok bash -c '. "$1"/init; use deps; deps_path env >/dev/null' _ "$NUTSHELL_ROOT"
}

#[test]
it_refuses_an_absent_tool_through_every_door() {
    local absent=definitely_not_a_real_tool_xyzzy
    assert_fails deps_has_all "$absent"
    assert_fails deps_has_any "$absent"
    assert_fails deps_run "$absent" true
    assert_fails deps_path "$absent"
}
