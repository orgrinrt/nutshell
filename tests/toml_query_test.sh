#!/usr/bin/env bash
# Tests for `toml_find`, the files whose key holds a value, and `toml_comment`,
# the comment on or above a key.
#
# The prefilter in `toml_find` is a text scan, and the cases that matter are the
# ones a text scan gets wrong: the value inside a comment or another key, and
# the value the file spells differently from how the reader gives it.

use toml toml::find toml::comment test

_tq_dir() { mktemp -d; }

_tq_fixture() {
    local d="$1"
    printf 'id = "T1"\nbranch = "b1"\n' > "$d/a.toml"
    printf 'id = "T2"\nbranch = "T1"\n' > "$d/b.toml"
    printf '# id = "T1"\nid = "T3"\n' > "$d/c.toml"
    printf "id = 'T1'\n" > "$d/d.toml"
    printf 'id = "\\u0054\\u0031"\n' > "$d/e.toml"
    printf 'title = "x"\n[meta]\nid = "T1"\n' > "$d/f.toml"
    printf 'n = 0xFF\n' > "$d/g.toml"
    printf 'n = 1_000\n' > "$d/h.toml"
    printf 'note = """\nid = "T1"\n"""\nid = "T9"\n' > "$d/i.toml"
}

#[test]
it_finds_an_array_the_file_spells_over_several_lines() {
    # `toml_get` prints the array on one line, which is not the text the file
    # holds, so a text scan for it would rule the file out.
    local d; d="$(_tq_dir)"
    printf 'n = [\n  1,\n  2,\n]\n' > "$d/a.toml"
    local got; got="$(cd "$d" && toml_find n "[1, 2]" a.toml)"
    rm -rf "$d"
    assert_eq "$got" "a.toml"
}

#[test]
it_finds_the_files_whose_key_holds_the_value() {
    local d; d="$(_tq_dir)"; _tq_fixture "$d"
    local got; got="$(cd "$d" && toml_find id T1 a.toml b.toml c.toml d.toml f.toml i.toml)"
    rm -rf "$d"
    assert_eq "$got" $'a.toml\nd.toml'
}

#[test]
it_finds_a_value_a_string_spells_with_an_escape() {
    local d; d="$(_tq_dir)"; _tq_fixture "$d"
    local got; got="$(cd "$d" && toml_find id T1 e.toml)"
    rm -rf "$d"
    assert_eq "$got" "e.toml"
}

#[test]
it_finds_a_dotted_key_and_not_the_top_level_one_of_the_same_name() {
    local d; d="$(_tq_dir)"; _tq_fixture "$d"
    local got; got="$(cd "$d" && toml_find meta.id T1 a.toml f.toml)"
    rm -rf "$d"
    assert_eq "$got" "f.toml"
}

#[test]
it_finds_an_integer_the_file_spells_in_hex_or_with_underscores() {
    local d; d="$(_tq_dir)"; _tq_fixture "$d"
    local got; got="$(cd "$d" && toml_find n 255 g.toml h.toml)"
    local other; other="$(cd "$d" && toml_find n 1000 g.toml h.toml)"
    rm -rf "$d"
    assert_eq "$got" "g.toml"
    assert_eq "$other" "h.toml"
}

#[test]
it_answers_one_in_the_order_the_files_were_given() {
    local d; d="$(_tq_dir)"; _tq_fixture "$d"
    local got; got="$(cd "$d" && toml_find id T1 d.toml a.toml)"
    rm -rf "$d"
    assert_eq "$got" $'d.toml\na.toml'
}

#[test]
it_returns_one_and_prints_nothing_when_no_file_matches() {
    local d; d="$(_tq_dir)"; _tq_fixture "$d"
    local got rc=0; got="$(cd "$d" && toml_find id T1 b.toml c.toml)" || rc=$?
    rm -rf "$d"
    assert_eq "$rc" "1"
    assert_eq "$got" ""
}

#[test]
it_skips_a_file_that_is_not_there() {
    local d; d="$(_tq_dir)"; _tq_fixture "$d"
    local got; got="$(cd "$d" && toml_find id T1 nope.toml a.toml)"
    rm -rf "$d"
    assert_eq "$got" "a.toml"
}

#[test]
it_names_a_candidate_the_reader_refuses_and_returns_two() {
    local d; d="$(_tq_dir)"; _tq_fixture "$d"
    printf 'id = "T1"\nid = "T1"\n' > "$d/bad.toml"
    local got err rc=0
    got="$(cd "$d" && toml_find id T1 bad.toml a.toml 2>"$d/err")" || rc=$?
    err="$(cat "$d/err")"
    rm -rf "$d"
    assert_eq "$rc" "2"
    assert_eq "$got" "a.toml"
    assert_contains "$err" "defined twice"
}

#[test]
it_takes_a_value_with_a_newline_in_it() {
    local d; d="$(_tq_dir)"
    printf 'v = """\nx\ny"""\n' > "$d/a.toml"
    printf 'v = "x"\n' > "$d/b.toml"
    local got; got="$(cd "$d" && toml_find v $'x\ny' a.toml b.toml)"
    rm -rf "$d"
    assert_eq "$got" "a.toml"
}

_tq_comments() {
    printf '# above one\n# above two\na = 1 # trailing a\n\nb = 2\n\n# apart\n\nc = 3\n# for d\nd = 4\n[t]\ne = """\n# inside"""\nf = 5\n[[row]]\n# first\nid = 1\n' > "$1"
}

#[test]
it_prints_the_comment_above_a_key_then_the_one_after_its_value() {
    local d; d="$(_tq_dir)"; _tq_comments "$d/t.toml"
    local got; got="$(toml_comment "$d/t.toml" a)"
    rm -rf "$d"
    assert_eq "$got" $'above one\nabove two\ntrailing a'
}

#[test]
it_finds_no_comment_where_a_blank_line_parts_it_from_the_key() {
    local d; d="$(_tq_dir)"; _tq_comments "$d/t.toml"
    local rc=0 got; got="$(toml_comment "$d/t.toml" c)" || rc=$?
    rm -rf "$d"
    assert_eq "$rc" "1"
    assert_eq "$got" ""
}

#[test]
it_prints_the_comment_directly_above_a_key() {
    local d; d="$(_tq_dir)"; _tq_comments "$d/t.toml"
    local got; got="$(toml_comment "$d/t.toml" d)"
    rm -rf "$d"
    assert_eq "$got" "for d"
}

#[test]
it_does_not_read_the_last_line_of_a_multi_line_string_as_a_comment() {
    local d; d="$(_tq_dir)"; _tq_comments "$d/t.toml"
    local rc=0 got; got="$(toml_comment "$d/t.toml" t.f)" || rc=$?
    rm -rf "$d"
    assert_eq "$rc" "1"
    assert_eq "$got" ""
}

#[test]
it_reads_a_comment_in_a_row_of_an_array_of_tables() {
    local d; d="$(_tq_dir)"; _tq_comments "$d/t.toml"
    local got; got="$(toml_comment "$d/t.toml" row.0.id)"
    rm -rf "$d"
    assert_eq "$got" "first"
}

#[test]
it_returns_one_for_a_key_that_is_not_there_and_for_a_table() {
    local d; d="$(_tq_dir)"; _tq_comments "$d/t.toml"
    local rc=0 rc2=0
    toml_comment "$d/t.toml" nothing >/dev/null || rc=$?
    toml_comment "$d/t.toml" t >/dev/null || rc2=$?
    rm -rf "$d"
    assert_eq "$rc" "1"
    assert_eq "$rc2" "1"
}

#[test]
it_refuses_a_file_the_reader_refuses_when_asked_for_a_comment() {
    local d; d="$(_tq_dir)"
    printf 'a = 1\na = 2\n' > "$d/t.toml"
    local rc=0
    toml_comment "$d/t.toml" a >/dev/null 2>&1 || rc=$?
    rm -rf "$d"
    assert_eq "$rc" "2"
}

#[test]
it_finds_a_date_time_the_file_spells_with_lower_case_letters_or_a_space() {
    local d; d="$(_tq_dir)"
    printf 'at = 2024-05-06t10:00:00z\n' > "$d/a.toml"
    printf 'at = 2024-05-06 10:00:00Z\n' > "$d/b.toml"
    printf 'at = 2024-05-07T10:00:00Z\n' > "$d/c.toml"
    local got; got="$(cd "$d" && toml_find at 2024-05-06T10:00:00Z a.toml b.toml c.toml)"
    rm -rf "$d"
    assert_eq "$got" $'a.toml\nb.toml'
}

#[test]
it_finds_a_float_the_file_writes_with_underscores_and_a_sign() {
    local d; d="$(_tq_dir)"
    printf 'x = 1_000.5\n' > "$d/a.toml"
    printf 'x = +2.5\n' > "$d/b.toml"
    local one two
    one="$(cd "$d" && toml_find x 1000.5 a.toml b.toml)"
    two="$(cd "$d" && toml_find x 2.5 a.toml b.toml)"
    rm -rf "$d"
    assert_eq "$one" "a.toml"
    assert_eq "$two" "b.toml"
}
