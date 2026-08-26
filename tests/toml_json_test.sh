#!/usr/bin/env bash
# Tests for the TOML to JSON conversion.
#
# It had none, and two of the things it got wrong were the kind a test would
# have caught on the first run: `[a.b]` after `[a]` emitted a second `a` beside
# the first, and a string's TOML escapes were escaped a second time on the way
# out.

use toml::json test

_tj() { mktemp -d; }

# Is this actually JSON, according to something that is not us? Skipped where
# no parser is installed, which is why nothing relies on it alone.
_tj_parser() {
    if command -v jq >/dev/null 2>&1; then printf 'jq'; return 0; fi
    if command -v python3 >/dev/null 2>&1; then printf 'python3'; return 0; fi
    return 1
}
_tj_valid() {
    local doc="$1"
    case "$(_tj_parser)" in
        jq)      printf '%s' "$doc" | jq -e . >/dev/null 2>&1 ;;
        python3) printf '%s' "$doc" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 ;;
        *)       return 0 ;;
    esac
}

#[test]
it_rejects_a_document_that_is_not_json() {
    # The control for every test below that leans on _tj_valid. Without it a
    # broken checker would pass everything and say nothing.
    _tj_parser >/dev/null || return 0
    assert_fails _tj_valid '{"a":1,}'
    assert_ok _tj_valid '{"a":1}'
}

#[test]
it_converts_a_flat_file() {
    local d; d="$(_tj)"
    printf 'title = "t"\n\n[ui]\nwidth = 30\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"title":"t","ui":{"width":30}}'
}

#[test]
it_nests_a_subsection_inside_its_parent() {
    # `[a.b]` used to close `a` and open a second one, so the object carried
    # the key twice and a parser kept only one of them.
    local d; d="$(_tj)"
    printf '[a]\nx = 1\n\n[a.b]\ny = 2\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"x":1,"b":{"y":2}}}'
    assert_ok _tj_valid "$got"
}

#[test]
it_keeps_two_siblings_under_one_parent() {
    local d; d="$(_tj)"
    printf '[a]\nx = 1\n[a.b]\ny = 2\n[a.c]\nz = 3\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"x":1,"b":{"y":2},"c":{"z":3}}}'
    assert_ok _tj_valid "$got"
}

#[test]
it_nests_three_deep() {
    local d; d="$(_tj)"
    printf '[a.b.c]\nx = 1\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"b":{"c":{"x":1}}}}'
}

#[test]
it_refuses_a_file_that_comes_back_to_a_finished_section() {
    # One pass cannot reopen a closed object, and emitting the key twice is
    # worse than saying so.
    local d; d="$(_tj)"
    printf '[b]\nx = 1\n[a]\ny = 2\n[b.c]\nz = 3\n' > "$d/t.toml"
    local out; out="$(toml_to_json "$d/t.toml" 2>&1)"
    local rc=$?
    rm -rf "$d"
    assert_ne "$rc" "0"
    assert_contains "$out" "b.c"
}

#[test]
it_does_not_double_escape_a_quoted_string() {
    local d; d="$(_tj)"
    printf '[a]\nv = "say \\"hi\\""\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"v":"say \"hi\""}}'
    assert_ok _tj_valid "$got"
}

#[test]
it_does_not_double_escape_a_backslash() {
    local d; d="$(_tj)"
    printf '[a]\np = "C:\\\\tools"\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"p":"C:\\tools"}}'
    assert_ok _tj_valid "$got"
}

#[test]
it_writes_a_tab_as_a_json_escape_not_a_raw_tab() {
    # TOML's \t is a real tab by the time the value is read, and JSON will not
    # take one inside a string.
    local d; d="$(_tj)"
    printf '[a]\nv = "one\\ttwo"\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"v":"one\ttwo"}}'
    assert_ok _tj_valid "$got"
}

#[test]
it_leaves_a_literal_string_as_typed() {
    local d; d="$(_tj)"
    printf '[a]\np = \047C:\\tools\047\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"p":"C:\\tools"}}'
}

#[test]
it_writes_numbers_and_bools_bare() {
    local d; d="$(_tj)"
    printf '[a]\ni = -3\nf = 1.5\nt = true\nf2 = false\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"i":-3,"f":1.5,"t":true,"f2":false}}'
    assert_ok _tj_valid "$got"
}

#[test]
it_writes_an_array() {
    local d; d="$(_tj)"
    printf '[a]\nl = ["one", "two"]\ne = []\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"l":["one","two"],"e":[]}}'
    assert_ok _tj_valid "$got"
}

#[test]
it_ignores_comments_and_blank_lines() {
    local d; d="$(_tj)"
    printf '# leading\n\n[a]\n# about x\nx = 1  # trailing\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"x":1}}'
}

#[test]
it_converts_an_empty_file_to_an_empty_object() {
    local d; d="$(_tj)"
    : > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{}'
}

#[test]
it_refuses_a_file_that_is_not_there() {
    local d; d="$(_tj)"
    assert_fails toml_to_json "$d/nope.toml"
    rm -rf "$d"
}

#[test]
it_keeps_a_hash_that_is_part_of_a_value() {
    local d; d="$(_tj)"
    printf '[a]\nv = "#[pub]"\n' > "$d/t.toml"
    local got; got="$(toml_to_json "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" '{"a":{"v":"#[pub]"}}'
}
