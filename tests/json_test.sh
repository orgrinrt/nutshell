#!/usr/bin/env bash
# Tests for JSON, over every backend the machine has.
#
# The module picks one of jq, python and perl at load and dispatches on
# `_JSON_IMPL` at call time, so a test can set it and exercise each. Testing
# only whichever the machine happened to choose leaves two implementations of
# every function unexercised, and they are three separate pieces of code that
# have to agree.

use json deps test

# _impls -> the backends available here, one per line
_impls() {
    deps_has jq && printf 'jq\n'
    { deps_has python3 || deps_has python; } && printf 'python\n'
    deps_has perl && printf 'perl\n'
}

#[test]
it_has_a_backend() {
    assert_ok json_ready
    assert_ne "$(json_impl)" ""
}

#[test]
it_reads_a_top_level_value() {
    local impl
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        assert_eq "$(json_get '{"name":"alice"}' name)" "alice" "under ${impl}"
    done < <(_impls)
}

#[test]
it_reads_a_nested_value() {
    local impl
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        assert_eq "$(json_get '{"user":{"id":7}}' user.id)" "7" "under ${impl}"
    done < <(_impls)
}

#[test]
it_accepts_valid_json_and_refuses_invalid() {
    local impl
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        assert_ok json_valid '{"a":1}'
        assert_fails json_valid '{"a":'
    done < <(_impls)
}

#[test]
it_reports_the_type_of_a_value() {
    local impl
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        assert_eq "$(json_type '{"a":[1,2]}' a)" "array" "under ${impl}"
    done < <(_impls)
}

#[test]
it_counts_the_length_of_an_array() {
    local impl
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        assert_eq "$(json_length '{"a":[1,2,3]}' a)" "3" "under ${impl}"
    done < <(_impls)
}

#[test]
it_lists_the_keys_of_an_object() {
    local impl keys
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        keys="$(json_keys '{"a":1,"b":2}' | sort | tr '\n' ' ')"
        assert_eq "$keys" "a b " "under ${impl}"
    done < <(_impls)
}

#[test]
it_says_whether_a_key_is_there() {
    local impl
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        assert_ok json_has '{"a":1}' a
        assert_fails json_has '{"a":1}' b
    done < <(_impls)
}

#[test]
it_falls_back_when_a_key_is_absent() {
    local impl
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        assert_eq "$(json_get_or '{"a":1}' b fallback)" "fallback" "under ${impl}"
    done < <(_impls)
}
