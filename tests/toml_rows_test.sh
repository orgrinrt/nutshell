#!/usr/bin/env bash
# Tests for writing inside an array of tables: a row is reached by its index,
# `row.3.status`, and a new row is appended with `toml_append_table`.
#
# Every expected file is written out whole in the test. The law is that the
# write changes the one line and no other, so a test that read the value back
# would pass for a writer that rewrote the rest of the file.

use toml toml::write test

_tr_dir() { mktemp -d; }

# _tr_run <content> <fn> <args...> -> `_TR_BODY` the file after, `_TR_RC`,
# `_TR_OUT` stdout, `_TR_ERR` stderr
_tr_run() {
    local d; d="$(_tr_dir)"
    printf '%b' "$1" > "$d/t.toml"
    shift
    local fn="$1"; shift
    _TR_RC=0
    _TR_OUT="$("$fn" "$d/t.toml" "$@" 2>"$d/err")" || _TR_RC=$?
    _TR_ERR="$(cat "$d/err")"
    _TR_BODY="$(cat "$d/t.toml")"
    rm -rf "$d"
}

_TR_ROWS='[[row]]\nid = "a"\nstatus = "open"\n\n[[row]]\nid = "b"\nstatus = "open" # keep\n'

#[test]
it_sets_a_key_in_the_row_an_index_names() {
    _tr_run "$_TR_ROWS" toml_set row.1.status done
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_BODY" $'[[row]]\nid = "a"\nstatus = "open"\n\n[[row]]\nid = "b"\nstatus = "done" # keep'
}

#[test]
it_sets_a_key_in_the_first_row_and_leaves_the_second() {
    _tr_run "$_TR_ROWS" toml_set row.0.status closed
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_BODY" $'[[row]]\nid = "a"\nstatus = "closed"\n\n[[row]]\nid = "b"\nstatus = "open" # keep'
}

#[test]
it_adds_a_new_key_at_the_end_of_the_row_it_names() {
    _tr_run "$_TR_ROWS" toml_set row.0.note hello
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_BODY" $'[[row]]\nid = "a"\nstatus = "open"\nnote = "hello"\n\n[[row]]\nid = "b"\nstatus = "open" # keep'
}

#[test]
it_adds_a_key_to_a_row_that_has_a_table_under_it() {
    _tr_run '[[row]]\na = 1\n[row.sub]\nk = 1\n[[row]]\na = 2\n' toml_set row.0.b 7
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_BODY" $'[[row]]\na = 1\nb = 7\n[row.sub]\nk = 1\n[[row]]\na = 2'
}

#[test]
it_sets_a_key_in_a_table_under_a_row() {
    _tr_run '[[row]]\na = 1\n[row.sub]\nk = 1\n[[row]]\na = 2\n[row.sub]\nk = 2\n' toml_set row.1.sub.k 9
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_BODY" $'[[row]]\na = 1\n[row.sub]\nk = 1\n[[row]]\na = 2\n[row.sub]\nk = 9'
}

#[test]
it_unsets_a_key_in_the_row_an_index_names() {
    _tr_run "$_TR_ROWS" toml_unset row.1.status
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_BODY" $'[[row]]\nid = "a"\nstatus = "open"\n\n[[row]]\nid = "b"'
}

#[test]
it_unsets_a_key_that_a_row_lacks_and_leaves_the_file() {
    _tr_run "$_TR_ROWS" toml_unset row.0.nothing
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_BODY" $'[[row]]\nid = "a"\nstatus = "open"\n\n[[row]]\nid = "b"\nstatus = "open" # keep'
}

#[test]
it_unsets_in_a_row_that_is_not_there_without_touching_the_file() {
    _tr_run "$_TR_ROWS" toml_unset row.5.status
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_BODY" $'[[row]]\nid = "a"\nstatus = "open"\n\n[[row]]\nid = "b"\nstatus = "open" # keep'
}

#[test]
it_refuses_to_set_in_a_row_that_is_not_there() {
    _tr_run "$_TR_ROWS" toml_set row.5.status x
    assert_eq "$_TR_RC" "1"
    assert_eq "$_TR_BODY" $'[[row]]\nid = "a"\nstatus = "open"\n\n[[row]]\nid = "b"\nstatus = "open" # keep'
}

#[test]
it_still_refuses_a_key_with_no_index_in_an_array_of_tables() {
    _tr_run "$_TR_ROWS" toml_set row.status x
    assert_eq "$_TR_RC" "2"
    assert_contains "$_TR_ERR" "array of tables"
}

#[test]
it_refuses_to_set_a_row_itself_as_a_value() {
    _tr_run "$_TR_ROWS" toml_set row.0 x
    assert_eq "$_TR_RC" "2"
    assert_contains "$_TR_ERR" "table"
}

#[test]
it_refuses_a_dotted_key_inside_a_row() {
    _tr_run '[[row]]\na.b = 1\n' toml_set row.0.a.b 2
    assert_eq "$_TR_RC" "2"
    assert_contains "$_TR_ERR" "dotted key"
    assert_eq "$_TR_BODY" $'[[row]]\na.b = 1'
}

#[test]
it_refuses_an_inline_table_inside_a_row() {
    _tr_run '[[row]]\ni = { x = 1 }\n' toml_set row.0.i.x 2
    assert_eq "$_TR_RC" "2"
    assert_contains "$_TR_ERR" "inline table"
    assert_eq "$_TR_BODY" $'[[row]]\ni = { x = 1 }'
}

#[test]
it_refuses_to_open_a_table_under_a_row_by_a_header() {
    # `[row.new]` always names the last row, so it cannot say row 0.
    _tr_run "$_TR_ROWS" toml_set row.0.new.k 1
    assert_eq "$_TR_RC" "2"
    assert_contains "$_TR_ERR" "row"
    assert_eq "$_TR_BODY" $'[[row]]\nid = "a"\nstatus = "open"\n\n[[row]]\nid = "b"\nstatus = "open" # keep'
    # The last row too: the writer refuses a header under any row, as its
    # docblock says, and leaves the file as it was.
    _tr_run "$_TR_ROWS" toml_set row.1.new.k 1
    assert_eq "$_TR_RC" "2"
    assert_eq "$_TR_BODY" $'[[row]]\nid = "a"\nstatus = "open"\n\n[[row]]\nid = "b"\nstatus = "open" # keep'
}

#[test]
it_appends_a_table_after_the_last_row_of_the_array() {
    _tr_run '[[row]]\nid = "a"\n\n[other]\nx = 1\n' toml_append_table row
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_OUT" "row.1"
    assert_eq "$_TR_BODY" $'[[row]]\nid = "a"\n\n[[row]]\n\n[other]\nx = 1'
}

#[test]
it_appends_a_table_after_the_tables_under_the_last_row() {
    _tr_run '[[row]]\na = 1\n[row.sub]\nk = 1\n[other]\nx = 1\n' toml_append_table row
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_OUT" "row.1"
    assert_eq "$_TR_BODY" $'[[row]]\na = 1\n[row.sub]\nk = 1\n\n[[row]]\n[other]\nx = 1'
}

#[test]
it_appends_the_first_table_of_an_array_at_the_end_of_the_file() {
    _tr_run 'x = 1\n' toml_append_table row
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_OUT" "row.0"
    assert_eq "$_TR_BODY" $'x = 1\n\n[[row]]'
}

#[test]
it_appends_the_first_table_to_an_empty_file_without_a_blank_line() {
    _tr_run '' toml_append_table row
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_BODY" '[[row]]'
}

#[test]
it_appends_past_the_comments_that_end_the_file() {
    _tr_run '[[row]]\na = 1\n# the end\n' toml_append_table row
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_BODY" $'[[row]]\na = 1\n# the end\n\n[[row]]'
}

#[test]
it_appends_a_table_to_a_nested_array() {
    _tr_run '[a]\nx = 1\n' toml_append_table a.row
    assert_eq "$_TR_RC" "0"
    assert_eq "$_TR_OUT" "a.row.0"
    assert_eq "$_TR_BODY" $'[a]\nx = 1\n\n[[a.row]]'
}

#[test]
it_sets_a_key_in_the_table_it_just_appended() {
    local d; d="$(_tr_dir)"
    printf '[[row]]\nid = "a"\n' > "$d/t.toml"
    local p; p="$(toml_append_table "$d/t.toml" row)"
    toml_set "$d/t.toml" "$p.id" b
    local body; body="$(cat "$d/t.toml")"
    local count; count="$(toml_table_count "$d/t.toml" row)"
    rm -rf "$d"
    assert_eq "$body" $'[[row]]\nid = "a"\n\n[[row]]\nid = "b"'
    assert_eq "$count" "2"
}

#[test]
it_refuses_to_append_a_table_where_a_table_or_a_value_is() {
    _tr_run '[row]\nx = 1\n' toml_append_table row
    assert_eq "$_TR_RC" "2"
    assert_eq "$_TR_BODY" $'[row]\nx = 1'
    _tr_run 'row = 1\n' toml_append_table row
    assert_eq "$_TR_RC" "2"
    assert_eq "$_TR_BODY" 'row = 1'
}

#[test]
it_refuses_to_append_a_table_inside_an_inline_table_or_by_an_index() {
    _tr_run 'i = { x = 1 }\n' toml_append_table i.row
    assert_eq "$_TR_RC" "2"
    assert_eq "$_TR_BODY" 'i = { x = 1 }'
    _tr_run '[[row]]\na = 1\n' toml_append_table row.0.sub
    assert_eq "$_TR_RC" "2"
    assert_eq "$_TR_BODY" $'[[row]]\na = 1'
}

#[test]
it_refuses_to_append_to_a_file_the_reader_refuses() {
    _tr_run 'a = 1\na = 2\n' toml_append_table row
    assert_eq "$_TR_RC" "2"
    assert_contains "$_TR_ERR" "defined twice"
}

#[test]
it_keeps_the_line_endings_of_a_file_that_ends_its_lines_with_carriage_returns() {
    _tr_run '[[row]]\r\na = 1\r\n' toml_append_table row
    assert_eq "$_TR_BODY" $'[[row]]\r\na = 1\r\n\r\n[[row]]\r'
    _tr_run '[[row]]\r\na = 1\r\n[[row]]\r\na = 2\r\n' toml_set row.0.b 3
    assert_eq "$_TR_BODY" $'[[row]]\r\na = 1\r\nb = 3\r\n[[row]]\r\na = 2\r'
}
