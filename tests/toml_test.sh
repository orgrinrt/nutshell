#!/usr/bin/env bash
# Tests for the TOML reader.
#
# Both of the first two pin bugs that shipped: values containing `#` were
# truncated as comments, and an array with a trailing comma reported failure
# after parsing correctly. Neither had a test, and both were found only because
# a config value happened to contain the characters that broke them.

use toml test

FIXTURE="${BASH_SOURCE[0]%/*}/fixtures/sample.toml"

#[test]
it_reads_a_plain_value() {
    assert_eq "$(toml_get "$FIXTURE" "meta.name")" "sample"
}

#[test]
it_keeps_a_hash_inside_a_quoted_value() {
    # `_toml_clean_line` truncated at the first `#` regardless of quotes, so
    # every value containing one silently became empty.
    assert_eq "$(toml_get "$FIXTURE" "annotations.public_api")" "#[pub]"
}

#[test]
it_still_strips_a_real_trailing_comment() {
    # The control: quote-awareness must not stop it stripping actual comments.
    assert_eq "$(toml_get "$FIXTURE" "meta.version")" "1.0.0"
}

#[test]
it_reads_an_array_with_a_trailing_comma() {
    # TOML permits the trailing comma. The reader populated the array and then
    # returned failure, because its last statement was a test against the empty
    # final element.
    local -a out=()
    assert_ok toml_array "$FIXTURE" "lists.with_trailing_comma" out
    assert_eq "${#out[@]}" "2"
}

#[test]
it_reads_bracket_bearing_array_values() {
    local -a out=()
    toml_array "$FIXTURE" "lists.attributes" out
    assert_eq "${out[0]}" "#[pub]"
    assert_eq "${out[1]}" "#[allow(trivial_wrapper)]"
}

#[test]
it_reports_a_missing_key_rather_than_inventing_one() {
    assert_fails toml_get "$FIXTURE" "meta.nothing_here"
}
