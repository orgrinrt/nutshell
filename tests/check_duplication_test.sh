#!/usr/bin/env bash
# Tests for the cross-file duplicate-name comparison.
#
# The check compares function names across files, so a module split into two
# files trips it on the shared prefix alone: `toml_get` and `toml_set` score
# 0.875 while naming opposite operations. What is asserted here is that the
# prefix no longer carries a match on its own, and, more importantly, that the
# check can still catch the copy it exists for.

use test

NUT_CHECK_LOAD_ONLY=1 . "${BASH_SOURCE[0]%/*}/../examples/checks/check_function_duplication.sh"

# The comparison takes "name|file" lines and prints a MATCH line per pair.
_pairs() { compare_full_names "$1" "0.85"; }

#[test]
it_catches_the_same_function_copied_into_another_file() {
    # The positive control. Without it every result below is a claim about a
    # comparison that might match nothing at all.
    local out; out="$(_pairs "$(printf 'parse_the_line|a.sh\nparse_the_lines|b.sh\n')")"
    assert_contains "$out" "MATCH"
    assert_contains "$out" "parse_the_line"
}

#[test]
it_does_not_call_a_getter_and_a_setter_a_duplicate() {
    local out; out="$(_pairs "$(printf 'toml_get|lib/toml.sh\ntoml_set|lib/toml/write.sh\n')")"
    assert_empty "$out"
}

#[test]
it_does_not_call_two_more_operations_of_one_module_duplicates() {
    local out; out="$(_pairs "$(printf 'huli_run|a.sh\nhuli_add|b.sh\n')")"
    assert_empty "$out"
}

#[test]
it_still_catches_a_copy_that_shares_the_module_prefix() {
    # The guard is about the prefix carrying a match on its own. Two names in
    # one family whose own halves also look alike are still a copy.
    local out; out="$(_pairs "$(printf 'toml_read_value|a.sh\ntoml_read_values|b.sh\n')")"
    assert_contains "$out" "MATCH"
}

#[test]
it_ignores_a_pair_that_lives_in_one_file() {
    # A getter and a setter side by side are the ordinary way to write a
    # module, and the check has never been about that.
    local out; out="$(_pairs "$(printf 'json_get|lib/json.sh\njson_set|lib/json.sh\n')")"
    assert_empty "$out"
}

#[test]
it_ignores_names_that_do_not_look_alike() {
    local out; out="$(_pairs "$(printf 'toml_get|a.sh\nfs_mkdir|b.sh\n')")"
    assert_empty "$out"
}

#[test]
it_matches_the_identical_name_in_two_files() {
    local out; out="$(_pairs "$(printf 'do_the_thing|a.sh\ndo_the_thing|b.sh\n')")"
    assert_contains "$out" "MATCH"
    assert_contains "$out" "1.000"
}

#[test]
it_does_not_compare_a_name_with_no_prefix_by_a_prefix_rule() {
    # Nothing to strip, so the guard must not fire and swallow the match.
    local out; out="$(_pairs "$(printf 'render|a.sh\nrenders|b.sh\n')")"
    assert_contains "$out" "MATCH"
}
