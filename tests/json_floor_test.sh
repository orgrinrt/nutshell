#!/usr/bin/env bash
# Tests for the JSON reader that needs no tool, and for what json refuses
# where it has none.
#
# A container with no jq, no python and no perl has to be able to read JSON.
# Every test that depends on a tool being absent hides it from `deps` rather
# than relying on the machine lacking it, so the answer is the same on a
# laptop with all three installed.

use json deps test
source "${BASH_SOURCE[0]%/*}/fixtures/hide_tools.sh"

# A document with every kind of value, written out of order on purpose.
_JF_DOC='{"b":2,"a":{"y":[1,{"q":"x\ty","p":null}],"x":true},"e":{},"k.d":{"z":1}}'

# What a machine with only the floor looks like.
_jf_bare() {
    _hide_tools jq gojq jaq python python3 perl
    json_detect
}

#[test]
it_reads_a_value_with_jq_python_and_perl_hidden() {
    _jf_bare
    assert_eq "$(json_impl)" "bash"
    assert_eq "$(json_get '{"a":{"b":[10,20]}}' a.b.1)" "20"
}

#[test]
it_reads_a_leading_dot_path_like_the_other_backends() {
    _jf_bare
    assert_eq "$(json_get '{"a":{"b":[7,8]}}' .a.b.0)" "7"
}

#[test]
it_reads_a_quoted_key_as_one_segment() {
    _jf_bare
    assert_eq "$(json_get "$_JF_DOC" '"k.d".z')" "1"
}

#[test]
it_prints_a_container_compact_with_sorted_keys() {
    _jf_bare
    assert_eq "$(json_get "$_JF_DOC" a)" '{"x":true,"y":[1,{"p":null,"q":"x\ty"}]}'
    assert_eq "$(json_get "$_JF_DOC" a.y.1)" '{"p":null,"q":"x\ty"}'
    assert_eq "$(json_get "$_JF_DOC" e)" '{}'
}

#[test]
it_decodes_escapes_in_a_string() {
    _jf_bare
    assert_eq "$(json_get '{"s":"café 😀 \"q\" \\ \/"}' s)" 'café 😀 "q" \ /'
}

#[test]
it_prints_scalars_as_json() {
    _jf_bare
    assert_eq "$(json_get '{"t":true,"f":false,"n":null,"i":-12,"d":1.5}' t)" "true"
    assert_eq "$(json_get '{"t":true,"f":false,"n":null,"i":-12,"d":1.5}' f)" "false"
    assert_eq "$(json_get '{"t":true,"f":false,"n":null,"i":-12,"d":1.5}' n)" "null"
    assert_eq "$(json_get '{"t":true,"f":false,"n":null,"i":-12,"d":1.5}' i)" "-12"
    assert_eq "$(json_get '{"t":true,"f":false,"n":null,"i":-12,"d":1.5}' d)" "1.5"
}

#[test]
it_says_absent_with_status_one_and_null_is_present() {
    _jf_bare
    json_get '{"a":1}' zzz >/dev/null 2>&1; assert_eq "$?" "1"
    json_get '{"a":{"b":1}}' a.zzz >/dev/null 2>&1; assert_eq "$?" "1"
    json_get '[1,2]' 5 >/dev/null 2>&1; assert_eq "$?" "1"
    json_get '{"a":null}' a >/dev/null 2>&1; assert_eq "$?" "0"
}

#[test]
it_answers_has_keys_type_and_length() {
    _jf_bare
    assert_ok json_has "$_JF_DOC" a.x
    assert_fails json_has "$_JF_DOC" a.nope
    assert_eq "$(json_keys "$_JF_DOC" | tr '\n' ' ')" "a b e k.d "
    assert_eq "$(json_keys '[5,6,7]' | tr '\n' ' ')" "0 1 2 "
    assert_eq "$(json_type "$_JF_DOC" a)" "object"
    assert_eq "$(json_type "$_JF_DOC" a.y)" "array"
    assert_eq "$(json_type "$_JF_DOC" a.y.1.q)" "string"
    assert_eq "$(json_type "$_JF_DOC" b)" "number"
    assert_eq "$(json_type "$_JF_DOC" a.x)" "boolean"
    assert_eq "$(json_type "$_JF_DOC" a.y.1.p)" "null"
    assert_eq "$(json_length "$_JF_DOC" a.y)" "2"
    assert_eq "$(json_length "$_JF_DOC")" "4"
}

#[test]
it_counts_a_strings_length_in_characters_in_any_locale() {
    # jq's `length` on these strings, written in: 1, 5 and 4 characters, of 2,
    # 6 and 10 bytes. The escaped form is decoded first, so it counts the same.
    _jf_bare
    local loc
    for loc in C POSIX C.UTF-8; do
        assert_eq "$(LC_ALL=$loc json_length '{"a":"é"}' a)" "1" "under ${loc}"
        assert_eq "$(LC_ALL=$loc json_length '{"a":"héllo"}' a)" "5" "under ${loc}"
        assert_eq "$(LC_ALL=$loc json_length '{"a":"a😀éb"}' a)" "4" "under ${loc}"
    done
}

#[test]
it_takes_the_last_of_a_repeated_key() {
    _jf_bare
    assert_eq "$(json_get '{"a":1,"a":2}' a)" "2"
}

#[test]
it_accepts_json_and_refuses_what_is_not() {
    _jf_bare
    assert_ok json_valid ' { "a" : [ 1 , 2 ] } '
    assert_ok json_valid '"just a string"'
    assert_ok json_valid '-0.5e+3'
    assert_fails json_valid '{"a":'
    assert_fails json_valid '{"a":1,}'
    assert_fails json_valid '[1 2]'
    assert_fails json_valid '{"a":1} x'
    assert_fails json_valid "{'a':1}"
    assert_fails json_valid '{"a":01}'
    assert_fails json_valid '{"a":"x
y"}'
    assert_fails json_valid '{"a":"\x"}'
    json_get '{"a":' a >/dev/null 2>&1; assert_eq "$?" "1"
}

#[test]
it_refuses_a_writer_with_status_two_and_names_the_tools() {
    _jf_bare
    local fn out rc
    for fn in "json_set {} a 1" "json_delete {} a" "json_merge {} {}" "json_pretty {}" "json_compact {}"; do
        out="$(${fn} 2>&1 >/dev/null)"; rc=$?
        assert_eq "$rc" "2" "$fn"
        assert_contains "$out" "jq, python or perl" "$fn"
    done
}

#[test]
it_refuses_a_path_whose_quote_never_closes() {
    _jf_bare
    json_get '{"a":1}' '"a' >/dev/null 2>&1; assert_eq "$?" "2"
}

#[test]
it_refuses_a_query_with_no_jq_family_tool() {
    _hide_tools jq gojq jaq
    json_detect
    local out rc
    out="$(json_query '.a' '{"a":1}' 2>&1 >/dev/null)"; rc=$?
    assert_eq "$rc" "2"
    assert_contains "$out" "jq, gojq or jaq"
}

#[test]
it_runs_a_query_through_jq_when_it_is_there() {
    deps_has jq || { skip "jq is not on this machine"; return 0; }
    assert_eq "$(json_query '.a | length' '{"a":[1,2,3]}')" "3"
    assert_eq "$(json_query '.a' '{"a":"x"}')" "x"
    assert_eq "$(json_query '[.a,.b]' '{"b":2,"a":1}')" "[1,2]"
    assert_eq "$(printf '{"a":5}' | json_query '.a + 1')" "6"
}

# A stand-in that says which tool ran, for the order jq > gojq > jaq.
_jf_fake() {
    local dir="$1" name="$2"
    mkdir -p "$dir"
    printf '#!/bin/sh\necho "%s ran"\n' "$name" > "$dir/$name"
    chmod +x "$dir/$name"
}

#[test]
it_prefers_gojq_to_jaq_and_jq_to_both() {
    local t; t="$(mktemp -d)"
    _jf_fake "$t/bin" gojq; _jf_fake "$t/bin" jaq
    PATH="$t/bin:$PATH"
    _hide_tools jq
    json_detect
    assert_eq "$(json_query '.' '{}')" "gojq ran"
    _hide_tools gojq
    json_detect
    assert_eq "$(json_query '.' '{}')" "jaq ran"
    rm -rf "$t"
}

#[test]
it_reads_a_document_and_a_string_longer_than_its_buffer() {
    # The reader works through a buffer of a few KB, so what sits across a
    # refill is where it would be wrong: an escape split by the end of the
    # buffer, a number, a literal. The padding walks the escape over every
    # offset near the boundary.
    _jf_bare
    local pad x doc n want got
    for n in 4070 4080 4085 4088 4090 4092 4094 4096 4098 4100 8190 8200; do
        pad="$(printf '%*s' "$n" '' | tr ' ' x)"
        doc="{\"a\":\"${pad}\\u00e9\\ud83d\\ude00z\",\"b\":[12345,true,null,false],\"c\":${n}}"
        want="${pad}é😀z"
        got="$(json_get "$doc" a)"
        assert_eq "$got" "$want" "string, pad $n"
        assert_eq "$(json_get "$doc" b)" '[12345,true,null,false]' "array, pad $n"
        assert_eq "$(json_get "$doc" c)" "$n" "number, pad $n"
    done
    doc="[$(printf '%s,' $(seq 1 3000))0]"
    assert_eq "$(json_length "$doc")" "3001"
    assert_eq "$(json_get "$doc" 2999)" "3000"
}

#[test]
it_refuses_a_document_nested_past_its_limit_instead_of_overflowing() {
    _jf_bare
    local open close i
    open=""; close=""
    for i in $(seq 1 500); do open+="["; close+="]"; done
    assert_fails json_valid "${open}${close}"
    open=""; close=""
    for i in $(seq 1 100); do open+="["; close+="]"; done
    assert_ok json_valid "${open}${close}"
}
