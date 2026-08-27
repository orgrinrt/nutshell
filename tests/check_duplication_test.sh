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

# --- two spellings of one module are not a copy ------------------------------
#
# A `when=` row means a module is written twice for two shells, holding the
# same function names on purpose, and only one is ever loaded. Every pair of
# them scores 1.000 and none of them is a duplicate.
#
# The paths matter here and are the reason this test exists. `_variant_pairs`
# emitted absolute paths while `collect_all_functions` produces repo-relative
# ones, so the skip never matched and never fired on real data. It was proved
# working on hand-made absolute input, which is a test of the input.

_dup_lib() {
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-dup.XXXXXX")"
    printf '%s' "$1" > "$d/lib.nut"
    printf '%s' "$d"
}

#[test]
it_does_not_call_two_variants_of_one_module_a_duplicate() {
    local d; d="$(_dup_lib 'thing  lib/thing.sh        when=shell:bash4
thing  lib/thing.posix.sh')"
    local pairs; pairs="$(REPO_ROOT="$d" _variant_pairs)"
    # Relative, as `collect_all_functions` produces them.
    assert_contains "$pairs" "lib/thing.sh>lib/thing.posix.sh"
    assert_eq "${pairs#*/Users}" "$pairs" "the pairs must not be absolute"

    local out
    out="$(NUT_DUP_VARIANTS="$pairs" compare_full_names \
        "$(printf 'thing_do|lib/thing.sh\nthing_do|lib/thing.posix.sh\n')" "0.85")"
    assert_empty "$out"
    rm -rf "$d"
}

#[test]
it_still_calls_the_same_name_in_two_unrelated_files_a_duplicate() {
    # The control. A skip that fired on every pair would empty this check and
    # it would report clean over a library full of copies.
    local out
    out="$(NUT_DUP_VARIANTS="lib/a.sh>lib/b.sh" compare_full_names \
        "$(printf 'thing_do|lib/c.sh\nthing_do|lib/d.sh\n')" "0.85")"
    assert_contains "$out" "MATCH"
}

#[test]
it_carries_the_file_through_the_stripped_comparison() {
    # `add_stripped_names` emitted three fields and the comparison downstream
    # read `$4` for the file, so `files[]` was empty on every row of that pass:
    # it could not name a file in its own report and could not tell two
    # spellings of one module apart.
    local rows; rows="$(add_stripped_names "$(printf 'str_contains|lib/string.sh\n')")"
    assert_eq "$(awk -F'|' '{print NF}' <<<"$rows")" "4"
    assert_contains "$rows" "lib/string.sh"
}
