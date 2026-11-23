#!/usr/bin/env bash
# Tests for the options `json_query` passes to jq, gojq or jaq.
#
# The workspace's scripts call jq with variables (`--arg`, `--argjson`,
# `--slurpfile`, `--rawfile`), raw or slurped or null input, and the exit status
# of the result. `json_query` takes those and gives them to whichever tool
# `deps` picks, and where the tool it would pick lacks one it picks another
# that has it, or refuses with status 2 naming the option.
#
# Two kinds of test. Those on the real jq compare with text jq 1.7 printed,
# written in as literals. Those on gojq and jaq use stand-ins that print the
# arguments they were given, because what is under test is what reaches the
# tool: which tool, with which flags, in which order.

use json deps test
source "${BASH_SOURCE[0]%/*}/fixtures/hide_tools.sh"

# A stand-in that prints its own name and its arguments on one line.
_jq_fake() {
    local dir="$1" name="$2"
    mkdir -p "$dir"
    printf '#!/bin/sh\necho "%s $*"\n' "$name" > "$dir/$name"
    chmod +x "$dir/$name"
}

# _jq_only_real -> skip text when there is no jq to test against, else nothing
_jq_need_jq() {
    deps_has jq && return 0
    skip "jq is not on this machine"
    return 1
}

# -----------------------------------------------------------------------------
# Real jq: the output convention and each option family
# -----------------------------------------------------------------------------

#[test]
it_keeps_strings_bare_and_the_rest_compact_by_default() {
    _jq_need_jq || return 0
    assert_eq "$(json_query '.a' '{"a":"x"}')" "x"
    assert_eq "$(json_query '.a' '{"a":{"b":[1,2]}}')" '{"b":[1,2]}'
}

#[test]
it_binds_a_string_variable_with_arg() {
    _jq_need_jq || return 0
    assert_eq "$(json_query --arg n 42 '.[$n]' '{"42":"hit"}')" "hit"
    assert_eq "$(json_query --arg n 42 --arg m b '[$n,$m]' '{}')" '["42","b"]'
}

#[test]
it_binds_a_json_variable_with_argjson() {
    _jq_need_jq || return 0
    assert_eq "$(json_query --argjson n 42 '.[0] + $n' '[1]')" "43"
    assert_eq "$(json_query --argjson o '{"k":[1]}' '$o' '{}')" '{"k":[1]}'
}

#[test]
it_binds_a_variable_from_a_file_with_slurpfile_and_rawfile() {
    _jq_need_jq || return 0
    local d; d="$(mktemp -d)"
    printf '1 2\n' > "$d/two.json"
    printf 'a\nb\n' > "$d/raw.txt"
    assert_eq "$(json_query --slurpfile s "$d/two.json" '$s' '{}')" '[1,2]'
    assert_eq "$(json_query --rawfile r "$d/raw.txt" '$r | length' '{}')" '4'
    rm -rf "$d"
}

#[test]
it_reads_null_input_slurped_input_and_raw_input() {
    _jq_need_jq || return 0
    assert_eq "$(json_query -n '1 + 1')" "2"
    assert_eq "$(printf '1 2 3\n' | json_query -s 'add')" "6"
    assert_eq "$(printf 'a\nb\n' | json_query -R '. + "!"')" "$(printf 'a!\nb!')"
    assert_eq "$(printf 'a\nb\n' | json_query -Rs 'split("\n") | length')" "3"
}

#[test]
it_takes_short_options_in_one_cluster() {
    _jq_need_jq || return 0
    assert_eq "$(json_query -nr '"a" + "b"')" "ab"
    assert_eq "$(printf 'a\nb\n' | json_query -Rs 'length')" "4"
    assert_eq "$(json_query -n --arg v x '$v')" "x"
}

#[test]
it_prints_json_text_when_asked_with_json_and_join_output_with_j() {
    _jq_need_jq || return 0
    assert_eq "$(json_query --json -n '"a"')" '"a"'
    assert_eq "$(printf 'a\nb\n' | json_query --json -Rs '.')" '"a\nb\n"'
    assert_eq "$(json_query -j -n '"a","b"')" "ab"
}

#[test]
it_gives_the_exit_status_of_the_result_with_e() {
    _jq_need_jq || return 0
    json_query -e '.a' '{"a":1}' >/dev/null
    assert_eq "$?" "0"
    json_query -e '.a' '{"a":false}' >/dev/null
    assert_eq "$?" "1"
    json_query -e '.a' '{"a":null}' >/dev/null
    assert_eq "$?" "1"
    json_query '.a' '{"a":false}' >/dev/null
    assert_eq "$?" "0" "without -e a false result is a success"
}

#[test]
it_refuses_an_option_it_does_not_know_with_status_2_naming_it() {
    _jq_need_jq || return 0
    local out rc
    out="$(json_query --frobnicate '.a' '{}' 2>&1)"; rc=$?
    assert_eq "$rc" "2"
    assert_contains "$out" "--frobnicate"
    out="$(json_query -nz '.a' 2>&1)"; rc=$?
    assert_eq "$rc" "2"
    assert_contains "$out" "-z"
}

#[test]
it_refuses_a_variable_option_with_no_name_and_value() {
    _jq_need_jq || return 0
    local out rc
    out="$(json_query --arg n 2>&1)"; rc=$?
    assert_eq "$rc" "2"
    assert_contains "$out" "--arg"
    assert_contains "$out" "--arg"
}

# -----------------------------------------------------------------------------
# gojq and jaq: what reaches the tool
# -----------------------------------------------------------------------------

#[test]
it_hands_every_option_family_to_gojq_as_it_took_it() {
    local t; t="$(mktemp -d)"
    _jq_fake "$t/bin" gojq
    PATH="$t/bin:$PATH"
    _hide_tools jq jaq
    json_detect
    assert_eq "$(json_query '.a' '{}')" "gojq -c -r .a"
    assert_eq "$(json_query --arg n v '.a' '{}')" "gojq -c -r --arg n v .a"
    assert_eq "$(json_query --argjson n 1 '.a' '{}')" "gojq -c -r --argjson n 1 .a"
    assert_eq "$(json_query --slurpfile n /f '.a' '{}')" "gojq -c -r --slurpfile n /f .a"
    assert_eq "$(json_query --rawfile n /f '.a' '{}')" "gojq -c -r --rawfile n /f .a"
    assert_eq "$(json_query -n -s -R -e '.a' '{}')" "gojq -c -r -n -s -R -e .a"
    assert_eq "$(json_query -nc '.a')" "gojq -c -r -n .a"
    assert_eq "$(json_query --json '.a' '{}')" "gojq -c .a"
    assert_eq "$(json_query -j '.a' '{}')" "gojq -c -j .a"
    rm -rf "$t"
}

#[test]
it_hands_the_options_jaq_has_to_jaq() {
    local t; t="$(mktemp -d)"
    _jq_fake "$t/bin" jaq
    PATH="$t/bin:$PATH"
    _hide_tools jq gojq
    json_detect
    assert_eq "$(json_query --arg n v '.a' '{}')" "jaq -c -r --arg n v .a"
    assert_eq "$(json_query --argjson n 1 '.a' '{}')" "jaq -c -r --argjson n 1 .a"
    assert_eq "$(json_query -n -s -R '.a' '{}')" "jaq -c -r -n -s -R .a"
    rm -rf "$t"
}

#[test]
it_refuses_what_jaq_lacks_when_jaq_is_all_there_is() {
    local t out rc opt; t="$(mktemp -d)"
    _jq_fake "$t/bin" jaq
    PATH="$t/bin:$PATH"
    _hide_tools jq gojq
    json_detect
    for opt in "-e" "--slurpfile n /f" "--rawfile n /f"; do
        # shellcheck disable=SC2086
        out="$(json_query $opt '.a' '{}' 2>&1)"; rc=$?
        assert_eq "$rc" "2" "$opt"
        assert_contains "$out" "${opt%% *}" "$opt"
        assert_contains "$out" "jaq" "$opt"
    done
    rm -rf "$t"
}

#[test]
it_picks_another_tool_for_a_call_the_first_cannot_make() {
    local t; t="$(mktemp -d)"
    _jq_fake "$t/bin" gojq; _jq_fake "$t/bin" jaq
    PATH="$t/bin:$PATH"
    # Only jaq and gojq here, so jq is hidden: jaq is third in the order, but
    # gojq is first of the two and has every option.
    _hide_tools jq
    json_detect
    assert_eq "$(json_query -e '.a' '{}')" "gojq -c -r -e .a"
    # With gojq hidden as well, jaq is the only one and `-e` is refused.
    _hide_tools gojq
    json_detect
    json_query -e '.a' '{}' >/dev/null 2>&1
    assert_eq "$?" "2"
    # A call jaq can make still goes to jaq.
    assert_eq "$(json_query -n '.a')" "jaq -c -r -n .a"
    rm -rf "$t"
}

#[test]
it_keeps_jq_for_a_call_jaq_cannot_make() {
    # jq has every option, so a call jaq cannot make is not moved off jq:
    # the order jq, gojq, jaq holds for every call jq can make.
    _jq_need_jq || return 0
    local t; t="$(mktemp -d)"
    _jq_fake "$t/bin" gojq; _jq_fake "$t/bin" jaq
    PATH="$PATH:$t/bin"
    json_detect
    assert_eq "$(json_query -e '.a' '{"a":3}')" "3"
    rm -rf "$t"
}
