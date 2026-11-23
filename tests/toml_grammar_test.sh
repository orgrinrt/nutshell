#!/usr/bin/env bash
# Tests for the TOML grammar the reader covers, one per construct it used to
# get wrong or miss.
#
# Every expected value below is a literal copied from mikefarah yq v4.44.3,
# `yq -p toml -o json -I0 <file>` or `yq -p toml '<path>' <file>` on the same
# fixture. The test never runs yq. Where yq cannot read a valid file, the
# comment on that test names the equivalent file yq was run on instead.

use toml toml::json test

_tg() { printf '%s/fixtures/toml/%s' "${BASH_SOURCE[0]%/*}" "$1"; }

# rc of a call that is expected to be refused, with its stderr kept.
_tg_refused() {
    _TG_ERR="$("$@" 2>&1 >/dev/null)" && return 0
    return $?
}

#[test]
it_reads_dotted_keys_at_the_root_and_in_a_table() {
    local f; f="$(_tg dotted_keys.toml)"
    assert_eq "$(toml_get "$f" fruit.apple.color)" "red"
    assert_eq "$(toml_get "$f" fruit.apple.size)" "3"
    assert_eq "$(toml_get "$f" fruit.banana)" "yellow"
    assert_eq "$(toml_get "$f" server.net.port)" "80"
    assert_eq "$(toml_to_json "$f")" '{"fruit":{"apple":{"color":"red","size":3},"banana":"yellow"},"server":{"net":{"port":80,"host":"localhost"}}}'
}

#[test]
it_reads_a_quoted_key_holding_a_dot_as_one_segment() {
    local f; f="$(_tg quoted_dot_key.toml)"
    assert_eq "$(toml_get "$f" '"quoted.dot"')" "root"
    assert_eq "$(toml_get "$f" 'site."google.com"')" "true"
    assert_eq "$(toml_get "$f" 'hosts."a.b"')" "dotted"
    assert_fails toml_get "$f" quoted.dot
    assert_eq "$(toml_to_json "$f")" '{"quoted.dot":"root","site":{"google.com":true},"hosts":{"a.b":"dotted"}}'
}

#[test]
it_reads_plain_and_literal_quoted_keys_without_the_quotes() {
    local f; f="$(_tg quoted_keys.toml)"
    assert_eq "$(toml_get "$f" 'quoted key')" "1"
    assert_eq "$(toml_get "$f" '"quoted key"')" "1"
    assert_eq "$(toml_get "$f" 'lit key')" "2"
    assert_eq "$(toml_get "$f" bare-key_1)" "3"
    assert_eq "$(toml_get "$f" escAped)" "4"
    assert_eq "$(toml_to_json "$f")" '{"quoted key":1,"lit key":2,"bare-key_1":3,"escAped":4}'
}

#[test]
it_reads_quoted_section_headers() {
    local f; f="$(_tg quoted_headers.toml)"
    assert_eq "$(toml_get "$f" '"quoted sect".k')" "1"
    assert_eq "$(toml_get "$f" 'a."b.c".d.k')" "3"
    assert_eq "$(toml_get "$f" '"lit sect".k')" "4"
    assert_ok toml_has_section "$f" '"quoted sect"'
    assert_eq "$(toml_sections "$f")" $'"quoted sect"\na."b.c".d\n"lit sect"'
    assert_eq "$(toml_to_json "$f")" '{"quoted sect":{"k":1},"a":{"b.c":{"d":{"k":3}}},"lit sect":{"k":4}}'
}

#[test]
it_reads_an_array_of_tables() {
    # yq panics on the empty `[[products]]` and cannot index `[servers.opts]`
    # under an array of tables, both valid TOML. Its literals come from the
    # equivalent inline file: products = [ { name = "Hammer", sku = 738594937
    # }, {}, { name = "Nail", sku = 284758393 } ], servers = [ { name =
    # "alpha", opts = { fast = true } }, { name = "beta" } ].
    local f; f="$(_tg array_of_tables.toml)"
    assert_eq "$(toml_table_count "$f" products)" "3"
    assert_eq "$(toml_get "$f" products.0.name)" "Hammer"
    assert_eq "$(toml_get "$f" products.2.name)" "Nail"
    assert_fails toml_get "$f" products.1.name
    assert_eq "$(toml_tables "$f" products)" $'products.0\nproducts.1\nproducts.2'
    assert_ok toml_has_section "$f" products
    assert_eq "$(toml_table_count "$f" servers)" "2"
    assert_eq "$(toml_get "$f" servers.0.opts.fast)" "true"
    assert_eq "$(toml_get "$f" servers.1.name)" "beta"
    assert_fails toml_get "$f" servers.opts.fast
    assert_eq "$(toml_to_json "$f")" '{"products":[{"name":"Hammer","sku":738594937},{},{"name":"Nail","sku":284758393}],"servers":[{"name":"alpha","opts":{"fast":true}},{"name":"beta"}]}'
}

#[test]
it_counts_no_tables_where_the_path_is_not_an_array_of_tables() {
    local f; f="$(_tg dotted_keys.toml)"
    assert_fails toml_table_count "$f" fruit
    assert_fails toml_tables "$f" nothing.here
}

#[test]
it_converts_an_array_of_tables_to_an_array() {
    assert_eq "$(toml_to_json "$(_tg aot_twice.toml)")" '{"p":[{"name":"a"},{"name":"b"}]}'
}

#[test]
it_converts_an_inline_table_to_an_object() {
    assert_eq "$(toml_to_json "$(_tg inline_table.toml)")" '{"i":{"x":1,"y":"two"},"n":{"a":{"b":1},"c":{"d":"e"}},"empty":{},"pts":[{"x":1},{"x":2}]}'
}

#[test]
it_converts_a_multi_line_string() {
    local f; f="$(_tg ml_string.toml)"
    assert_eq "$(toml_to_json "$f")" '{"ml":"line one\nline \"two\" with \"\"quotes\"\"\n","lit":"raw \\n kept\n","after":1}'
    assert_eq "$(toml_get "$f" ml)" $'line one\nline "two" with ""quotes""'
    assert_eq "$(toml_get "$f" lit)" 'raw \n kept'
    assert_eq "$(toml_get "$f" after)" "1"
}

#[test]
it_converts_a_multi_line_array() {
    local f; f="$(_tg ml_array.toml)"
    assert_eq "$(toml_to_json "$f")" '{"a":[1,2,3],"nested":[["x","y"],["z"]],"z":3}'
    local -a got=()
    assert_ok toml_array "$f" a got
    assert_eq "${got[*]}" "1 2 3"
    assert_eq "$(toml_get "$f" nested.1.0)" "z"
    assert_eq "$(toml_get "$f" a.2)" "3"
    assert_eq "$(toml_get "$f" z)" "3"
}

#[test]
it_folds_a_line_ending_backslash_in_a_multi_line_basic_string() {
    local f; f="$(_tg ml_fold.toml)"
    assert_eq "$(toml_get "$f" folded)" "The quick brown fox."
    assert_eq "$(toml_get "$f" kept)" $'a\\\nb'
    assert_eq "$(toml_to_json "$f")" '{"folded":"The quick brown fox.","kept":"a\\\nb"}'
}

#[test]
it_reaches_into_an_inline_table_by_the_same_path() {
    local f; f="$(_tg inline_table.toml)"
    assert_eq "$(toml_get "$f" i.x)" "1"
    assert_eq "$(toml_get "$f" i.y)" "two"
    assert_eq "$(toml_get "$f" n.a.b)" "1"
    assert_eq "$(toml_get "$f" n.c.d)" "e"
    assert_eq "$(toml_get "$f" pts.1.x)" "2"
    assert_eq "$(toml_get "$f" i)" '{ x = 1, y = "two" }'
}

#[test]
it_skips_a_byte_order_mark() {
    # yq refuses the BOM itself; its literal is from the same file without it.
    local f; f="$(_tg bom.toml)"
    assert_eq "$(toml_get "$f" title)" "bom"
    assert_eq "$(toml_to_json "$f")" '{"title":"bom","next":2}'
}

#[test]
it_converts_values_by_their_type() {
    local f; f="$(_tg types.toml)"
    assert_eq "$(toml_to_json "$f")" '{"i":1000,"h":255,"o":15,"neg":-3,"pi":7,"f":3.14,"fu":1000.5,"t":true,"dt":"1979-05-27T07:32:00Z","do":"1979-05-27T00:32:00.999-07:00"}'
    assert_eq "$(toml_get "$f" i)" "1000"
    assert_eq "$(toml_get "$f" h)" "255"
    assert_eq "$(toml_get "$f" o)" "15"
    assert_eq "$(toml_get "$f" pi)" "7"
    assert_eq "$(toml_get "$f" fu)" "1000.5"
    assert_eq "$(toml_get "$f" dt)" "1979-05-27T07:32:00Z"
}

#[test]
it_reads_a_padded_section_header() {
    local f; f="$(_tg padded_header.toml)"
    assert_eq "$(toml_get "$f" sp.k)" "2"
    assert_eq "$(toml_get "$f" outer.inner.k)" "5"
    assert_ok toml_has_section "$f" sp
    assert_eq "$(toml_sections "$f")" $'sp\nouter.inner'
    assert_eq "$(toml_to_json "$f")" '{"sp":{"k":2},"outer":{"inner":{"k":5}}}'
}

# What the reader refuses rather than guesses at. Each is invalid TOML, so the
# answer is rc 2 and the construct named, never a miss that looks like rc 1.

_tg_bad() {
    local d; d="$(mktemp -d)"
    printf '%b' "$1" > "$d/t.toml"
    local rc=0
    _tg_refused toml_get "$d/t.toml" "${2:-a}" || rc=$?
    rm -rf "$d"
    _TG_RC="$rc"
}

#[test]
it_refuses_a_key_defined_twice() {
    _tg_bad 'a = 1\na = 2\n'
    assert_eq "$_TG_RC" "2"
    assert_contains "$_TG_ERR" "defined twice"
}

#[test]
it_refuses_a_table_defined_twice() {
    _tg_bad '[a]\nx = 1\n[a]\ny = 2\n' a.x
    assert_eq "$_TG_RC" "2"
    assert_contains "$_TG_ERR" "defined twice"
}

#[test]
it_refuses_an_escape_toml_does_not_have() {
    _tg_bad 'a = "x\\qy"\n'
    assert_eq "$_TG_RC" "2"
    assert_contains "$_TG_ERR" "escape"
}

#[test]
it_refuses_an_unterminated_string() {
    _tg_bad 'a = "open\nb = 1\n' b
    assert_eq "$_TG_RC" "2"
    assert_contains "$_TG_ERR" "unterminated"
}

#[test]
it_refuses_an_integer_past_the_64_bit_range() {
    # TOML 1.0: an integer that cannot be held losslessly is an error. Both
    # are nineteen digits, one past each end of the range.
    _tg_bad 'a = 9223372036854775808\n'
    assert_eq "$_TG_RC" "2"
    assert_contains "$_TG_ERR" "out of range"
    _tg_bad 'a = -9223372036854775809\n'
    assert_eq "$_TG_RC" "2"
}

#[test]
it_reads_the_two_ends_of_the_64_bit_range() {
    local d; d="$(mktemp -d)"
    printf 'hi = 9223372036854775807\nlo = -9223372036854775808\n' > "$d/t.toml"
    assert_eq "$(toml_get "$d/t.toml" hi)" "9223372036854775807"
    assert_eq "$(toml_get "$d/t.toml" lo)" "-9223372036854775808"
    rm -rf "$d"
}

#[test]
it_reads_a_signed_zero_as_the_integer_zero() {
    # `-0` and `+0` are the integer 0 as taplo and mikefarah yq both give it,
    # `{"a":0,"b":0}` from each, so the floor says the same and a file converted
    # to JSON reads alike whoever read it.
    _toml_parse_text t $'a = -0\nb = +0\nc = 0\n'
    assert_eq "${_TOML_V[R${_TOML_US}a]}" "0"
    assert_eq "${_TOML_V[R${_TOML_US}b]}" "0"
    assert_eq "${_TOML_V[R${_TOML_US}c]}" "0"
    assert_eq "${_TOML_T[R${_TOML_US}a]}" "int"
}

#[test]
it_refuses_a_bare_word_as_a_value() {
    _tg_bad 'a = hello\n'
    assert_eq "$_TG_RC" "2"
    assert_contains "$_TG_ERR" "value"
}

#[test]
it_refuses_an_inline_table_that_spans_lines() {
    _tg_bad 'a = { x = 1,\n  y = 2 }\n' a.x
    assert_eq "$_TG_RC" "2"
    assert_contains "$_TG_ERR" "inline table"
}

#[test]
it_refuses_a_dotted_key_that_extends_an_inline_table() {
    _tg_bad 'a = { x = 1 }\na.y = 2\n' a.x
    assert_eq "$_TG_RC" "2"
    assert_contains "$_TG_ERR" "inline table"
}

#[test]
it_refuses_a_header_over_a_table_made_by_dotted_keys() {
    _tg_bad '[a]\nb.c = 1\n[a.b]\nd = 2\n' a.b.c
    assert_eq "$_TG_RC" "2"
    assert_contains "$_TG_ERR" "dotted"
}

#[test]
it_passes_a_refusal_through_has_and_get_or_rather_than_calling_it_a_miss() {
    local d; d="$(mktemp -d)"
    printf 'a = 1\na = 2\nb = 3\n' > "$d/t.toml"
    local rc=0
    toml_has "$d/t.toml" b 2>/dev/null || rc=$?
    assert_eq "$rc" "2"
    rc=0
    toml_get_or "$d/t.toml" zz fallback >/dev/null 2>&1 || rc=$?
    rm -rf "$d"
    assert_eq "$rc" "2"
}

#[test]
it_refuses_to_convert_infinity_which_json_has_no_spelling_for() {
    local d; d="$(mktemp -d)"
    printf 'x = inf\n' > "$d/t.toml"
    local rc=0
    _tg_refused toml_to_json "$d/t.toml" || rc=$?
    local got; got="$(toml_get "$d/t.toml" x)"
    rm -rf "$d"
    assert_eq "$rc" "2"
    assert_contains "$_TG_ERR" "inf"
    assert_eq "$got" "inf"
}
