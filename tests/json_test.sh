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
# that call. `_agrees_read` is the same over the readers, which include the one
# that needs no tool, the only one that does not write.
#
# The arguments are passed through, not assembled into a string and eval'd. The
# first version of this did eval, and `{"a":1,"b":2}` on a command line is a
# brace expansion: bash tore the document into words before the function saw
# it, every backend was handed the same nonsense, they agreed about it, and the
# test passed with the bug it was written for put back.
_agrees() { _agrees_over _impls "$@"; }
_agrees_read() { _agrees_over _readers "$@"; }

# _readers -> every backend that reads, the floor last
_readers() { _impls; printf 'bash\n'; }

_agrees_over() {
    local lister="$1" impl first="" seen=0 got rc
    shift
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        got="$("$@" 2>/dev/null)"; rc=$?
        if [[ "$seen" -eq 0 ]]; then
            first="${got}|${rc}"
            seen=1
        else
            assert_eq "${got}|${rc}" "$first" "${impl} on: $*"
        fi
    done < <("$lister")
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

    _agrees_read json_get "$doc" b.c
    _agrees_read json_get "$doc" d
    _agrees_read json_keys "$doc"
    _agrees_read json_type "$doc" b
    _agrees_read json_length "$doc" b.c
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
    _agrees_read json_get '{"k":"café"}' k

    # An integer path segment indexes an array. jq built its path by putting a
    # dot in front, and `.1` is not the second element, it is the number 0.1.
    _agrees_read json_get '[10,20]' 1
    _agrees_read json_get '{"a":[10,20]}' a.1

    # An absent key is absent. jq and perl said `null` with a zero status,
    # which cannot be told from a key that is present and null, and python said
    # nothing with a status of 1.
    _agrees_read json_get '{"a":1}' zzz
    _agrees_read json_get '{"a":{"b":1}}' a.zzz

    # Scalars come back as JSON, not as whatever the tool's own language
    # prints. Python said `True` and perl said `1`.
    _agrees_read json_get '{"a":true}' a
    _agrees_read json_get '{"a":false}' a
    _agrees_read json_get '{"a":null}' a
    _agrees_read json_get '{"a":1.5}' a

    # A quote inside a string. Python returned nothing at all.
    _agrees_read json_get '{"a":"he said \"hi\""}' a

    # Empty containers, and a value that is one.
    _agrees json_compact '{}'
    _agrees json_compact '[]'
    _agrees json_compact '{"a":[[1,2],[3]]}'
    _agrees_read json_type '{"a":null}' a
    _agrees_read json_keys '{"a":[1,2]}' a
    _agrees json_set '{"a":{"b":1}}' a.b 9
    _agrees json_delete '{"a":{"b":1,"c":2}}' a.b
}

#[test]
it_reads_the_dotted_path_language_the_same_on_every_backend() {
    # A leading dot, an index, and a quoted segment holding a dot: the language
    # the toml reader speaks, so one path reads a file in either format. The
    # expected values are written here, from what jq prints for the same path,
    # so agreement is not agreement on a shared mistake.
    local doc='{"a":{"b":[7,8,{"c":"deep"}]},"k.d":{"z":1},"x y":2}' impl
    while IFS= read -r impl; do
        _JSON_IMPL="$impl"
        assert_eq "$(json_get "$doc" .a.b.0)" "7" "$impl .a.b.0"
        assert_eq "$(json_get "$doc" a.b.2.c)" "deep" "$impl a.b.2.c"
        assert_eq "$(json_get "$doc" '"k.d".z')" "1" "$impl quoted key"
        assert_eq "$(json_get "$doc" '"x y"')" "2" "$impl quoted key with a space"
        json_get "$doc" 'k.d.z' >/dev/null 2>&1; assert_eq "$?" "1" "$impl a split that is not there"
    done < <(_readers)
}

# --- the jq backend's own classifiers ----------------------------------------

#[test]
it_tells_a_json_literal_from_a_string() {
    # This replaced `[[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]` and three `==`
    # comparisons, because `[[ ]]` is bash and this file is on the POSIX
    # floor. A `case` recognising the same shape is easy to get subtly wrong
    # in either direction: too loose and a string gets injected into the jq
    # program unquoted, too tight and a number arrives quoted.
    deps_has jq || { skip "jq is not on this machine"; return 0; }

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
    deps_has jq || { skip "jq is not on this machine"; return 0; }

    # Segments arrive already split, joined by the unit separator, so a key
    # holding a dot is one segment.
    local us; us="$(printf '\037')"
    assert_eq "$(_jq_path '')" "."
    assert_eq "$(_jq_path "a")" '.["a"]'
    assert_eq "$(_jq_path "a${us}b")" '.["a"]["b"]'
    assert_eq "$(_jq_path "1")" '.[1]'
    assert_eq "$(_jq_path "a${us}1")" '.["a"][1]'
    assert_eq "$(_jq_path "1${us}a")" '.[1]["a"]'
    assert_eq "$(_jq_path "a-b")" '.["a-b"]'
    assert_eq "$(_jq_path "k.d${us}z")" '.["k.d"]["z"]'
    assert_eq "$(_jq_path "say \"hi\"")" '.["say \"hi\""]'
    assert_eq "$(_jq_path "a*b")" '.["a*b"]'
    assert_eq "$(_jq_path "*")" '.["*"]'
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

# -----------------------------------------------------------------------------
# json_set creates a missing parent, the way jq does
# -----------------------------------------------------------------------------
#
# jq's `.a.b.c = 1` on `{}` makes `{"a":{"b":{"c":1}}}`, a null on the way is
# replaced, and a number segment makes an array, padded with null. Python
# answered 1 and perl answered `{}`, so the same call built a document or none
# by whichever tool was installed. The literals are what jq 1.7 printed.

# _has_impl <name> -> 0 when this machine has that backend
_has_impl() {
    case "$1" in
        jq)     deps_has jq ;;
        python) deps_has python3 || deps_has python ;;
        perl)   deps_has perl ;;
    esac
}

# _set_creates <backend> -> asserts the parents are made, or skips by name
_set_creates() {
    local impl="$1"
    if ! _has_impl "$impl"; then skip "${impl} is not on this machine"; return 0; fi
    _JSON_IMPL="$impl"
    assert_eq "$(json_set '{}' a.b.c 1)" '{"a":{"b":{"c":1}}}' "three missing levels, under ${impl}"
    assert_eq "$(json_set '{}' a.b x)" '{"a":{"b":"x"}}' "a string value, under ${impl}"
    assert_eq "$(json_set '{"a":{"x":1}}' a.y.z 2)" '{"a":{"x":1,"y":{"z":2}}}' "beside a sibling, under ${impl}"
    assert_eq "$(json_set '{"a":null}' a.b 1)" '{"a":{"b":1}}' "a null on the way, under ${impl}"
    assert_eq "$(json_set '{}' a.b.1 x)" '{"a":{"b":[null,"x"]}}' "a number segment makes an array, under ${impl}"
    assert_eq "$(json_set '{"a":[1]}' a.3 9)" '{"a":[1,null,null,9]}' "an array grows, under ${impl}"
    assert_eq "$(json_set '[1]' 3 9)" '[1,null,null,9]' "a top-level array grows, under ${impl}"
    assert_eq "$(json_set '{"a":{"b":1}}' a.b 9)" '{"a":{"b":9}}' "an existing key is still replaced, under ${impl}"
}

#[test]
it_sets_through_missing_parents_under_jq() { _set_creates jq; }

#[test]
it_sets_through_missing_parents_under_python() { _set_creates python; }

#[test]
it_sets_through_missing_parents_under_perl() { _set_creates perl; }

#[test]
it_refuses_a_set_through_a_scalar_on_every_backend() {
    local impl out
    for impl in jq python perl; do
        _has_impl "$impl" || continue
        _JSON_IMPL="$impl"
        out="$(json_set '{"a":5}' a.b 1 2>/dev/null)"
        assert_fails json_set '{"a":5}' a.b 1
        assert_eq "$out" "" "no document is printed, under ${impl}"
    done
}

#[test]
it_builds_the_same_document_from_missing_parents_on_every_backend() {
    local impl first="" seen=0 got
    for impl in jq python perl; do
        _has_impl "$impl" || { skip "${impl} is not on this machine"; continue; }
        _JSON_IMPL="$impl"
        got="$(json_set '{"k":{"z":1}}' k.a.b.0.c true 2>&1)"
        if [ "$seen" -eq 0 ]; then first="$got"; seen=1
        else assert_eq "$got" "$first" "${impl} against the first backend"; fi
    done
    assert_eq "$first" '{"k":{"a":{"b":[{"c":true}]},"z":1}}'
}
