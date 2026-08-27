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
it_encodes_a_name_that_is_not_a_variable_name() {
    # The tool tables are one variable per entry, so the name is part of a
    # variable name. A name that already is one is used as itself, which is
    # what keeps `${_TOOL_PATH_jq}` a plain expansion in the sixteen modules
    # that read these literally.
    _deps_key sed;        assert_eq "$_dk" "sed"
    _deps_key grep_pcre;  assert_eq "$_dk" "grep_pcre"
    _deps_key _x;         assert_eq "$_dk" "_x"
    _deps_key a1;         assert_eq "$_dk" "a1"

    # Anything else is encoded rather than refused. An earlier version refused,
    # and `deps_has pkg-config` then answered yes with an empty path while
    # growing the available-tools list on every call. Half the binaries worth
    # asking about have a hyphen or a leading digit.
    _deps_key pkg-config; assert_ne "$_dk" "pkg-config"
    assert_eq "${_dk#enc_}" "706b672d636f6e666967"
    _deps_key 7z;         assert_eq "${_dk%${_dk#enc_}}" "enc_"

    # One to one, which is the property the whole scheme rests on. A safe name
    # beginning `enc_` takes the encoded path too, or it would collide with
    # whatever hex-encodes to it.
    _deps_key enc_706b67; local a="$_dk"
    _deps_key pkg;        local b="$_dk"
    assert_ne "$a" "$b"

    # Byte-wise, which is what makes the concatenation prefix-free. `printf
    # '%d' "'c"` gives a codepoint and `%02x` is a minimum width, so a
    # character above U+00FF produced four digits and one character could
    # occupy the space of two: `€` and a space followed by `¬` both encoded to
    # `20ac`, and the second name read the first's path.
    local a b
    _deps_key '€';  a="$_dk"
    _deps_key ' ¬'; b="$_dk"
    assert_ne "$a" "$b"
    assert_eq "$a" "enc_e282ac"
    assert_eq "$b" "enc_20c2ac"

    # `é` is two bytes and the raw byte 0xe9 is one. They collided at `e9`.
    _deps_key 'é'; assert_eq "$_dk" "enc_c3a9"

    # Every encoded name is an even number of hex digits, which is the property
    # the fixed width buys and the thing a variable width breaks.
    local n v
    for v in 'a-b' '7z' 'pkg-config' '€' 'é' 'a b' 'x.y'; do
        _deps_key "$v"
        n="${_dk#enc_}"
        assert_eq "$(( ${#n} % 2 ))" "0"
    done

    # And an empty name is not a name at all.
    assert_fails _deps_key ""
}

#[test]
it_does_not_let_two_tool_names_reach_one_variable() {
    # The property the whole scheme rests on, checked as a property rather than
    # on the pair that motivated it. Every name here must reach its own
    # variable; any two landing on one is a silent wrong-path bug in
    # `deps_path` and `deps_run`, which are public.
    local seen="" v k
    for v in sed grep_pcre _x a1 pkg-config git-lfs 7z 'a b' 'x.y' 'a+b' \
             '€' ' ¬' 'é' 'enc_706b67' pkg 'enc_' 'a' 'aa' 'a-' '-a'; do
        _deps_key "$v" || continue
        k="$_dk"
        assert_not_contains "$seen" "|${k}|"
        seen="${seen}|${k}|"
    done
}

#[test]
it_refuses_a_capability_name_that_is_not_a_variable_name() {
    # Capabilities are internal literals and are refused rather than encoded,
    # because `_TOOL_CAN_NAMES` is a space-separated list that `deps_caps`
    # splits. An encoded name and a raw one in one list disagree the moment
    # either holds a space, and `deps_caps` then emits two rows with empty
    # values.
    assert_fails _deps_can_set "a b" 1
    assert_fails _deps_can_set "a-b" 1
    assert_fails _deps_can_set "" 1
    assert_ok    _deps_can_set nut_test_cap 1
    assert_contains "$(deps_caps)" "nut_test_cap=1"
    # Every row still has a value, which is what a raw name in an encoded
    # table would have broken.
    assert_not_contains "$(deps_caps)" "="$'\n'
}

#[test]
it_resolves_a_tool_whose_name_is_not_a_variable_name() {
    # The regression this replaced a refusal to fix. Answering yes with an
    # empty path is worse than either answering no or answering correctly.
    command -v pkg-config >/dev/null 2>&1 || return 0

    assert_ok deps_has pkg-config
    local p; p="$(deps_path pkg-config)"
    assert_ne "$p" ""
    assert_ok test -x "$p"

    # And the miss is remembered, so the lookup does not re-fork forever. The
    # available list grew by one word per call when the write was silently
    # failing.
    local before after
    before="$(printf '%s' "$_TOOLS_AVAILABLE" | wc -w | tr -d ' ')"
    deps_has pkg-config; deps_has pkg-config; deps_has pkg-config
    after="$(printf '%s' "$_TOOLS_AVAILABLE" | wc -w | tr -d ' ')"
    assert_eq "$after" "$before"
}

#[test]
it_does_not_execute_what_a_caller_puts_in_a_tool_name() {
    # The negative control for the one above, driven through the public
    # surface rather than the validator, because that is where a caller
    # reaches it.
    # Encoded rather than refused now, so the defence is that the name never
    # reaches `eval` as text: it is hex by the time it gets there.
    local out
    out="$(deps_has 'x; echo PWNED' 2>&1; deps_path 'y$(echo PWNED)' 2>&1; deps_cap 'z`echo PWNED`' 2>&1)"
    assert_not_contains "$out" "PWNED"
    # And a name built to look like an assignment does not become one.
    deps_has 'q=1; echo PWNED2; :' >/dev/null 2>&1
    assert_eq "${q:-unset}" "unset"
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
    #
    # The `assert_not_contains` is the whole check. A `while | case ... return 1`
    # loop stood here and could not fail: the pipeline puts the loop in a
    # subshell, its status becomes the function's return value, and the harness
    # discards that in favour of the tally. Inverting the arm so every line took
    # the failing branch still reported a pass. It was four lines below the
    # commit that exists to fix exactly that class.
    assert_not_contains "$caps" "="$'\n'
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
