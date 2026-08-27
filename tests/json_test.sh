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
# Assert every available backend returns the same text and the same status for
# that call.
#
# The arguments are passed through, not assembled into a string and eval'd. The
# first version of this did eval, and `{"a":1,"b":2}` on a command line is a
# brace expansion: bash tore the document into words before the function saw
# it, every backend was handed the same nonsense, they agreed about it, and the
# test passed with the bug it was written for put back.
_agrees() {
    local impl first="" seen=0 got rc
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        got="$("$@" 2>/dev/null)"; rc=$?
        if [[ "$seen" -eq 0 ]]; then
            first="${got}|${rc}"
            seen=1
        else
            assert_eq "${got}|${rc}" "$first" "${impl} on: $*"
        fi
    done < <(_impls)
    assert_eq "$seen" "1" "at least one backend ran"
}

#[test]
it_returns_the_same_text_from_every_backend() {
    # The whole matrix, not a document chosen because it worked.
    #
    # The first version of this test asserted agreement over one hand-picked
    # object and passed, and the PR body then said the backends were
    # interchangeable. They were not: seven classes of disagreement were
    # sitting behind that green, and each is below. Choosing which inputs to
    # assert over is choosing what not to find out.
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

    # A merge is shallow. jq's `*` recurses into objects where python's
    # `update` and perl's slice assignment replace, so one call built a
    # different document depending on the tool installed.
    _agrees json_merge '{"a":{"b":1}}' '{"a":{"c":2}}'

    # Text outside ASCII. jq emits UTF-8, python escaped it to `\u00e9`, and
    # perl printed the bytes of a character string and produced mojibake.
    _agrees json_compact '{"k":"café"}'
    _agrees json_get '{"k":"café"}' k

    # An integer path segment indexes an array. jq built its path by putting a
    # dot in front, and `.1` is not the second element, it is the number 0.1.
    _agrees json_get '[10,20]' 1
    _agrees json_get '{"a":[10,20]}' a.1

    # An absent key is absent. jq and perl said `null` with a zero status,
    # which cannot be told from a key that is present and null, and python said
    # nothing with a status of 1.
    _agrees json_get '{"a":1}' zzz
    _agrees json_get '{"a":{"b":1}}' a.zzz

    # Scalars come back as JSON, not as whatever the tool's own language
    # prints. Python said `True` and perl said `1`.
    _agrees json_get '{"a":true}' a
    _agrees json_get '{"a":false}' a
    _agrees json_get '{"a":null}' a
    _agrees json_get '{"a":1.5}' a

    # A quote inside a string. Python returned nothing at all.
    _agrees json_get '{"a":"he said \"hi\""}' a

    # Empty containers, and a value that is one.
    _agrees json_compact '{}'
    _agrees json_compact '[]'
    _agrees json_compact '{"a":[[1,2],[3]]}'
    _agrees json_type '{"a":null}' a
    _agrees json_keys '{"a":[1,2]}' a
    _agrees json_set '{"a":{"b":1}}' a.b 9
    _agrees json_delete '{"a":{"b":1,"c":2}}' a.b
}

# --- the jq backend's own classifiers ----------------------------------------

#[test]
it_tells_a_json_literal_from_a_string() {
    # This replaced `[[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]` and three `==`
    # comparisons, because `[[ ]]` is bash and this file is on the POSIX
    # floor. A `case` recognising the same shape is easy to get subtly wrong
    # in either direction: too loose and a string gets injected into the jq
    # program unquoted, too tight and a number arrives quoted.
    deps_has jq || return 0

    for v in 1 -1 0 1.5 -1.5 10 -0.25 true false null '[1]' '[]' '{}' '{"a":1}'; do
        assert_ok _jq_is_json_literal "$v"
    done

    # The near misses. Each of these was accepted by neither the old regex nor
    # the new case, and each is a shape somebody would expect to work.
    for v in .5 5. 1.2.3 - -- --1 1a a1 abc '' ' ' 'true ' ' null' 0x10 1e5 +1; do
        assert_fails _jq_is_json_literal "$v"
    done
}

#[test]
it_builds_a_path_that_tells_an_index_from_a_name() {
    # A numeric segment is an array index and a name is a key, and putting a
    # dot in front of the whole path gets the first wrong: `.1` is the number
    # 0.1, not the second element. Bracket form for both, and a name quoted so
    # a key holding a dash or a space stays one segment.
    deps_has jq || return 0

    assert_eq "$(_jq_path '')" "."
    assert_eq "$(_jq_path '.')" "."
    assert_eq "$(_jq_path 'a')" '.["a"]'
    assert_eq "$(_jq_path '.a')" '.["a"]'
    assert_eq "$(_jq_path 'a.b')" '.["a"]["b"]'
    assert_eq "$(_jq_path '1')" '.[1]'
    assert_eq "$(_jq_path 'a.1')" '.["a"][1]'
    assert_eq "$(_jq_path '1.a')" '.[1]["a"]'
    assert_eq "$(_jq_path 'a-b')" '.["a-b"]'
    assert_eq "$(_jq_path 'a..b')" '.["a"]["b"]'
    # A segment holding a glob character must not be expanded by the split,
    # which is what `set -f` inside the loop is for.
    assert_eq "$(_jq_path 'a*b')" '.["a*b"]'
    assert_eq "$(_jq_path '*')" '.["*"]'
}

#[test]
# The escaping `json_object` and `json_array` do before they hand a value over.
#
# It was four `${value//from/to}` substitutions, which are bash's, and it had
# no test: the module's other tests all go through `jq` or `python`, which do
# their own escaping, so this path could have been broken in either direction
# without anything saying so.
#
# Backslash first, or the escaping escapes the backslashes it just added.
it_escapes_a_value_before_putting_it_in_an_object() {
    local v; v="$(printf 'a\\b"c\td\ne')"
    local got; got="$(json_object k "$v")"
    assert_eq "$got" '{"k":"a\\b\"c\td\ne"}'
}

#[test]
# The same for an array, which carries its own copy of the escaping.
it_escapes_a_value_before_putting_it_in_an_array() {
    local v; v="$(printf 'x"y\\z')"
    local got; got="$(json_array "$v")"
    assert_eq "$got" '["x\"y\\z"]'
}

#[test]
# A value that is only a backslash, which is where an ordering mistake shows
# up as one character instead of three.
it_escapes_a_lone_backslash_exactly_once() {
    local got; got="$(json_object k '\')"
    assert_eq "$got" '{"k":"\\"}'
}

#[test]
# `_json_gsub` refuses an out-name that is not one, and does not hang.
#
# Both were real. An empty search string matches everywhere and never shortens
# the remainder, so the loop appended forever; `str_replace` guards that on its
# first line and this copy did not. And the out-name goes into an `eval`, so
# `_json_gsub a b c 'v; echo X'` ran the echo.
it_refuses_a_bad_out_name_and_an_empty_needle() {
    local out=SENTINEL
    # An empty needle returns the subject unchanged rather than looping.
    assert_ok _json_gsub "abc" "" "X" out
    assert_eq "$out" "abc"

    # A name that is not a name is refused before it reaches `eval`.
    assert_fails _json_gsub "abc" "b" "Z" 'v; echo INJECTED'
    assert_fails _json_gsub "abc" "b" "Z" '1bad'
    assert_fails _json_gsub "abc" "b" "Z" ''

    # And nothing it refused was executed.
    local out2; out2="$(_json_gsub "abc" "b" "Z" 'v; echo INJECTED' 2>&1)"
    assert_not_contains "$out2" "INJECTED"

    # The control: an ordinary call still works.
    local ok=""
    assert_ok _json_gsub "abc" "b" "Z" ok
    assert_eq "$ok" "aZc"
}
