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

_JQ_FULL_HELP="--arg --argjson --slurpfile --rawfile -e, --exit-status"

# _jq_fake <dir> <name> [<help>] -> a stand-in that prints its own name and
# then each argument on a line of its own, so quoting reaches the test intact.
# Asked `--help`, it prints <help>, by default every option json_query passes.
_jq_fake() {
    local dir="$1" name="$2" help="${3-$_JQ_FULL_HELP}"
    mkdir -p "$dir"
    printf '#!/bin/sh\nif [ "$1" = --help ]; then echo "usage: %s %s"; exit 0; fi\nprintf "%%s\\n" %s "$@"\n' "$name" "$help" "$name" > "$dir/$name"
    chmod +x "$dir/$name"
}

# _jq_lines <word...> -> the words, one to a line, as a stand-in prints them
_jq_lines() { printf '%s\n' "$@"; }

# _jq_path <dir> -> PATH with <dir> first, and deps made to look again
_jq_path() { PATH="$1:$PATH"; deps_forget; json_detect; }

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
}

#[test]
it_binds_an_arg_value_with_spaces_and_quotes_as_one_string() {
    _jq_need_jq || return 0
    assert_eq "$(json_query -n --arg v 'a b "c" '"'"'d'"'"'' '$v')" "a b \"c\" 'd'"
    assert_eq "$(json_query -n --json --arg v 'a "b"' '$v')" '"a \"b\""'
}

#[test]
it_ends_options_at_a_double_dash() {
    _jq_need_jq || return 0
    local rc
    assert_eq "$(json_query -- '.a' '{"a":1}')" "1"
    # A filter that starts with `-`, as jq 1.7 prints it: `jq -n -- -1` gives -1.
    assert_eq "$(json_query -n -- '-1')" "-1"
    assert_eq "$(json_query -n -- '-1 | tostring')" "-1"
    # After `--` a word that looks like an option is the document.
    assert_eq "$(json_query -- '. + 1' '-1')" "0"
}

#[test]
it_takes_an_option_written_after_the_filter_as_an_option() {
    _jq_need_jq || return 0
    assert_eq "$(json_query '.a' --json '{"a":"x"}')" '"x"'
    assert_eq "$(json_query '.a' '{"a":"x"}' --json)" '"x"'
}

#[test]
it_refuses_more_than_a_filter_and_a_document_with_status_2() {
    _jq_need_jq || return 0
    local out rc
    out="$(json_query '.a' '{}' '{}' 2>&1)"; rc=$?
    assert_eq "$rc" "2"
    assert_contains "$out" "json_query"
    out="$(json_query -- '.a' '{}' extra 2>&1)"; rc=$?
    assert_eq "$rc" "2"
    assert_contains "$out" "extra"
}

#[test]
it_takes_the_long_option_forms() {
    _jq_need_jq || return 0
    assert_eq "$(json_query --null-input '1 + 1')" "2"
    assert_eq "$(printf '1 2 3\n' | json_query --slurp 'add')" "6"
    assert_eq "$(printf 'a\nb\n' | json_query --raw-input --slurp 'length')" "4"
    assert_eq "$(json_query --null-input --raw-output '"a"')" "a"
    assert_eq "$(json_query --null-input --join-output '"a","b"')" "ab"
    assert_eq "$(json_query --null-input --compact-output '{"a": [1, 2]}')" '{"a":[1,2]}'
    json_query --exit-status '.a' '{"a":false}' >/dev/null
    assert_eq "$?" "1"
    json_query --exit-status '.a' '{"a":null}' >/dev/null
    assert_eq "$?" "1"
    json_query --exit-status '.a' '{"a":0}' >/dev/null
    assert_eq "$?" "0"
}

#[test]
it_gives_status_1_for_a_query_the_tool_failed_and_keeps_2_for_a_refusal() {
    _jq_need_jq || return 0
    local out rc d; d="$(mktemp -d)"
    # jq 1.7 exits 2 on this: "Could not open ...: No such file or directory".
    out="$(json_query --slurpfile s "$d/none.json" '$s' '{}' 2>&1)"; rc=$?
    assert_eq "$rc" "1"
    assert_contains "$out" "none.json"
    json_query --frobnicate '.' '{}' >/dev/null 2>&1; rc=$?
    assert_eq "$rc" "2"
    rm -rf "$d"
}

# -----------------------------------------------------------------------------
# gojq and jaq: what reaches the tool
# -----------------------------------------------------------------------------

#[test]
it_hands_every_option_family_to_gojq_as_it_took_it() {
    local t; t="$(mktemp -d)"
    _jq_fake "$t/bin" gojq
    _jq_path "$t/bin"
    _hide_tools jq jaq
    assert_eq "$(json_query '.a' '{}')" "$(_jq_lines gojq -c -r .a)"
    assert_eq "$(json_query --arg n 'v w "x"' '.a' '{}')" "$(_jq_lines gojq -c -r --arg n 'v w "x"' .a)"
    assert_eq "$(json_query --argjson n 1 '.a' '{}')" "$(_jq_lines gojq -c -r --argjson n 1 .a)"
    assert_eq "$(json_query --slurpfile n /f '.a' '{}')" "$(_jq_lines gojq -c -r --slurpfile n /f .a)"
    assert_eq "$(json_query --rawfile n /f '.a' '{}')" "$(_jq_lines gojq -c -r --rawfile n /f .a)"
    assert_eq "$(json_query -n -s -R -e '.a' '{}')" "$(_jq_lines gojq -c -r -n -s -R -e .a)"
    assert_eq "$(json_query -nc '.a')" "$(_jq_lines gojq -c -r -n .a)"
    assert_eq "$(json_query --json '.a' '{}')" "$(_jq_lines gojq -c .a)"
    assert_eq "$(json_query -j '.a' '{}')" "$(_jq_lines gojq -c -j .a)"
    # A filter that starts with `-` reaches the tool led by a space, which every
    # jq family parser skips and no option parser takes for an option.
    assert_eq "$(json_query -n -- '-1')" "$(_jq_lines gojq -c -r -n ' -1')"
    rm -rf "$t"
}

#[test]
it_hands_the_options_a_jaq_lists_in_its_help_to_jaq() {
    local t; t="$(mktemp -d)"
    _jq_fake "$t/bin" jaq
    _jq_path "$t/bin"
    _hide_tools jq gojq
    assert_eq "$(json_query --arg n v '.a' '{}')" "$(_jq_lines jaq -c -r --arg n v .a)"
    assert_eq "$(json_query --argjson n 1 '.a' '{}')" "$(_jq_lines jaq -c -r --argjson n 1 .a)"
    assert_eq "$(json_query -n -s -R '.a' '{}')" "$(_jq_lines jaq -c -r -n -s -R .a)"
    assert_eq "$(json_query -e '.a' '{}')" "$(_jq_lines jaq -c -r -e .a)"
    assert_eq "$(json_query --slurpfile n /f '.a' '{}')" "$(_jq_lines jaq -c -r --slurpfile n /f .a)"
    assert_eq "$(json_query --rawfile n /f '.a' '{}')" "$(_jq_lines jaq -c -r --rawfile n /f .a)"
    rm -rf "$t"
}

#[test]
it_refuses_what_the_only_tool_does_not_list_in_its_help() {
    local t out rc opt; t="$(mktemp -d)"
    _jq_fake "$t/bin" jaq "--arg --argjson"
    _jq_path "$t/bin"
    _hide_tools jq gojq
    for opt in "-e" "--slurpfile n /f" "--rawfile n /f"; do
        # shellcheck disable=SC2086
        out="$(json_query $opt '.a' '{}' 2>&1)"; rc=$?
        assert_eq "$rc" "2" "$opt"
        assert_contains "$out" "${opt%% *}" "$opt"
        assert_contains "$out" "jaq" "$opt"
    done
    # A call it can make still goes to it.
    assert_eq "$(json_query -n '.a')" "$(_jq_lines jaq -c -r -n .a)"
    rm -rf "$t"
}

#[test]
it_moves_a_call_off_a_jq_whose_help_lacks_an_option_to_gojq() {
    # A jq before 1.6 has no --rawfile; the call goes to the next tool that has.
    local t; t="$(mktemp -d)"
    _jq_fake "$t/bin" jq "--arg --argjson --slurpfile -e, --exit-status"
    _jq_fake "$t/bin" gojq
    _jq_path "$t/bin"
    _hide_tools jaq
    assert_eq "$(json_query --rawfile n /f '.a' '{}')" "$(_jq_lines gojq -c -r --rawfile n /f .a)"
    # A call jq can make stays on jq.
    assert_eq "$(json_query --slurpfile n /f '.a' '{}')" "$(_jq_lines jq -c -r --slurpfile n /f .a)"
    rm -rf "$t"
}

#[test]
it_moves_a_call_off_jq_and_gojq_to_jaq_when_only_jaq_lists_the_option() {
    local t; t="$(mktemp -d)"
    _jq_fake "$t/bin" jq "--arg --argjson"
    _jq_fake "$t/bin" gojq "--arg --argjson --slurpfile"
    _jq_fake "$t/bin" jaq
    _jq_path "$t/bin"
    assert_eq "$(json_query -e '.a' '{}')" "$(_jq_lines jaq -c -r -e .a)"
    assert_eq "$(json_query --slurpfile n /f '.a' '{}')" "$(_jq_lines gojq -c -r --slurpfile n /f .a)"
    assert_eq "$(json_query '.a' '{}')" "$(_jq_lines jq -c -r .a)"
    rm -rf "$t"
}
