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

#[test]
it_merges_two_objects() {
    local impl
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        assert_eq "$(json_get "$(json_merge '{"a":1}' '{"b":2}')" b)" "2" "under ${impl}"
        assert_eq "$(json_get "$(json_merge '{"a":1}' '{"a":9}')" a)" "9" "under ${impl}"
    done < <(_impls)
}

#[test]
it_deletes_a_key() {
    local impl
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        assert_fails json_has "$(json_delete '{"a":1,"b":2}' a)" a
        assert_ok json_has "$(json_delete '{"a":1,"b":2}' a)" b
    done < <(_impls)
}

# _agrees <function> <args...>
#
# Assert every available backend returns the same text for that call.
#
# The arguments are passed through, not assembled into a string and eval'd.
# The first version of this did eval, and `{"a":1,"b":2}` on a command line is
# a brace expansion: bash tore the document into separate words before the
# function saw it, every backend was handed the same nonsense, they agreed
# about it, and the test passed with the bug it was written for put back.
_agrees() {
    local impl first="" seen=0 got
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        got="$("$@")"
        if [[ "$seen" -eq 0 ]]; then
            first="$got"
            seen=1
        else
            assert_eq "$got" "$first" "${impl} on: $*"
        fi
    done < <(_impls)
    assert_eq "$seen" "1" "at least one backend ran"
}

#[test]
it_returns_the_same_text_from_every_backend() {
    # The strongest test here. Three separate implementations of one contract
    # have to agree character for character, and two of them had never run on
    # any machine until the tool detection was fixed.
    #
    # Both disagreements found this way: jq's `del` printed formatted where the
    # others printed compact, and python's `json.dumps` puts a space after
    # every colon unless told not to.
    local doc='{"a":1,"b":{"c":[1,2,3]},"d":"x"}'

    _agrees json_get "$doc" b.c
    _agrees json_get "$doc" d
    _agrees json_keys "$doc"
    _agrees json_type "$doc" b
    _agrees json_length "$doc" b.c
    _agrees json_delete "$doc" a
    _agrees json_merge "$doc" '{"e":5}'
    _agrees json_compact "$doc"
    _agrees json_set "$doc" a 9
}
