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

# --- the tables are variables now, not associative arrays --------------------

#[test]
it_refuses_a_name_that_is_not_a_name() {
    # The tool tables are one variable per entry, so a name reaches `eval`.
    # `deps_has` takes whatever a caller hands it, which makes this the one
    # place where that matters, and the check is the whole defence.
    assert_fails _deps_name_ok 'x; echo pwned'
    assert_fails _deps_name_ok 'x$(echo pwned)'
    assert_fails _deps_name_ok 'x`echo pwned`'
    assert_fails _deps_name_ok 'a-b'
    assert_fails _deps_name_ok 'a b'
    assert_fails _deps_name_ok 'a.b'
    assert_fails _deps_name_ok ''
    assert_fails _deps_name_ok '1abc'
    # And the shapes that are names, or the check would pass by refusing
    # everything and the six above would prove nothing.
    assert_ok _deps_name_ok 'sed'
    assert_ok _deps_name_ok 'grep_pcre'
    assert_ok _deps_name_ok '_x'
    assert_ok _deps_name_ok 'a1'
}

#[test]
it_does_not_execute_what_a_caller_puts_in_a_tool_name() {
    # The negative control for the one above, driven through the public
    # surface rather than the validator, because that is where a caller
    # reaches it.
    local out
    out="$(deps_has 'x; echo PWNED' 2>&1; deps_path 'y$(echo PWNED)' 2>&1; deps_cap 'z`echo PWNED`' 2>&1)"
    assert_not_contains "$out" "PWNED"
}

#[test]
it_answers_the_same_through_the_accessor_and_the_variable() {
    # A literal read outside this module expands `${_TOOL_PATH_sed}` directly
    # and never calls the accessor. The two have to agree or every consumer
    # sees something different from what `deps_path` reports.
    deps_has sed || return 0
    local viafn viavar
    viafn="$(deps_path sed)"
    viavar="${_TOOL_PATH_sed:-}"
    assert_eq "$viavar" "$viafn"
    assert_ne "$viavar" ""
}

#[test]
it_lists_only_the_capabilities_that_were_set() {
    # `deps_caps` used to walk the keys of an associative array, so a
    # capability nobody set was absent rather than zero. Walking a fixed list
    # of every known capability instead would report the unset ones as zero,
    # which is a different answer, and this pins the one it gives.
    local caps; caps="$(deps_caps)"
    assert_ne "$caps" ""
    local n; n="$(printf '%s\n' "$caps" | wc -l | tr -d ' ')"
    local names; names="$(printf '%s' "$_TOOL_CAN_NAMES" | wc -w | tr -d ' ')"
    assert_eq "$n" "$names"
    # Every line is name=0 or name=1, never an empty value, which is what a
    # read through a missing variable would have produced.
    assert_not_contains "$caps" "="$'\n'
    printf '%s\n' "$caps" | while IFS= read -r line; do
        case "$line" in
            *=0|*=1) : ;;
            *) return 1 ;;
        esac
    done
}

#[test]
it_remembers_a_tool_it_could_not_find() {
    # A miss is paid for once. The table holding that is now a variable, so
    # this checks the variable rather than trusting the second call was fast.
    deps_has definitely_not_a_real_tool_xyzzy && return 1
    assert_eq "${_TOOL_MISSING_definitely_not_a_real_tool_xyzzy:-}" "1"
    deps_has definitely_not_a_real_tool_xyzzy && return 1
    return 0
}
