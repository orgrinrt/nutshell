#!/usr/bin/env bash
# Tests for the TOML writer.
#
# The whole point of a setter that edits in place rather than regenerating is
# that the file survives it: comments, order, blank lines, the neighbouring
# keys, and the key with the same name in the section next door. Most of these
# assert exactly that, because a writer that gets the value right and quietly
# eats the file around it looks correct in every test that only reads the
# value back.

use toml toml::write test

_tw_dir() { mktemp -d; }

_tw_sample() {
    cat > "$1" <<'EOF'
# The user's preferences. Hand-written, and it stays that way.
title = "root level"

[ui]
# how wide the sidebar wants to be
width = 30
theme = "dark"

# a pause the writer must not close up
[net]
width = 99
timeout = 5
EOF
}

#[test]
it_changes_a_value_in_place() {
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    assert_ok toml_set "$d/t.toml" "ui.theme" "light"
    local got; got="$(toml_get "$d/t.toml" ui.theme)"
    rm -rf "$d"
    assert_eq "$got" "light"
}

#[test]
it_keeps_the_comment_above_the_key_it_changed() {
    # The reason this function exists rather than a regenerate-from-model one.
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    toml_set "$d/t.toml" "ui.width" 42
    local body; body="$(cat "$d/t.toml")"
    rm -rf "$d"
    assert_contains "$body" "# how wide the sidebar wants to be"
}

#[test]
it_keeps_the_leading_comment_and_the_blank_lines() {
    # Counted before and after rather than against a number written here: the
    # law is that the write changes neither, and a hardcoded count only
    # asserts that somebody counted the fixture correctly.
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    local before; before="$(grep -c '^$' "$d/t.toml")"
    local before_lines; before_lines="$(wc -l < "$d/t.toml" | tr -d ' ')"
    toml_set "$d/t.toml" "ui.theme" "light"
    local after; after="$(grep -c '^$' "$d/t.toml")"
    local body; body="$(cat "$d/t.toml")"
    local lines; lines="$(wc -l < "$d/t.toml" | tr -d ' ')"
    rm -rf "$d"
    assert_contains "$body" "# The user's preferences."
    assert_contains "$body" "# a pause the writer must not close up"
    assert_eq "$after" "$before"
    assert_eq "$lines" "$before_lines"
}

#[test]
it_leaves_every_other_key_readable() {
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    toml_set "$d/t.toml" "ui.theme" "light"
    local w t n title
    w="$(toml_get "$d/t.toml" ui.width)"
    t="$(toml_get "$d/t.toml" net.timeout)"
    n="$(toml_get "$d/t.toml" net.width)"
    title="$(toml_get "$d/t.toml" title)"
    rm -rf "$d"
    assert_eq "$w" "30"
    assert_eq "$t" "5"
    assert_eq "$n" "99"
    assert_eq "$title" "root level"
}

#[test]
it_changes_only_the_key_in_the_named_section() {
    # `width` exists in both. A writer matching on the leaf alone hits the
    # first one it sees, which is the wrong file half the time.
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    toml_set "$d/t.toml" "net.width" 7
    local ui net
    ui="$(toml_get "$d/t.toml" ui.width)"
    net="$(toml_get "$d/t.toml" net.width)"
    rm -rf "$d"
    assert_eq "$ui" "30"
    assert_eq "$net" "7"
}

#[test]
it_appends_a_new_key_inside_its_own_section() {
    # Not at the end of the file, which is somebody else's section.
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    toml_set "$d/t.toml" "ui.density" "compact"
    local got line_ui line_new line_net
    got="$(toml_get "$d/t.toml" ui.density)"
    line_ui="$(grep -n '^\[ui\]' "$d/t.toml" | cut -d: -f1)"
    line_new="$(grep -n '^density' "$d/t.toml" | cut -d: -f1)"
    line_net="$(grep -n '^\[net\]' "$d/t.toml" | cut -d: -f1)"
    rm -rf "$d"
    assert_eq "$got" "compact"
    # Asserted, not stated. The harness counts assertions and ignores the exit
    # status by design, so a bare `(( ))` here was a no-op and the ordering the
    # test is named for went unchecked.
    assert_ok test "$line_ui" -lt "$line_new"
    assert_ok test "$line_new" -lt "$line_net"
}

#[test]
it_creates_a_section_that_is_not_there() {
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    assert_ok toml_set "$d/t.toml" "audio.volume" 80
    local got old
    got="$(toml_get "$d/t.toml" audio.volume)"
    old="$(toml_get "$d/t.toml" ui.theme)"
    rm -rf "$d"
    assert_eq "$got" "80"
    assert_eq "$old" "dark"
}

#[test]
it_writes_a_file_that_does_not_exist_yet() {
    local d; d="$(_tw_dir)"
    assert_ok toml_set "$d/new.toml" "ui.theme" "dark"
    local got; got="$(toml_get "$d/new.toml" ui.theme)"
    rm -rf "$d"
    assert_eq "$got" "dark"
}

#[test]
it_writes_a_root_level_key() {
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    toml_set "$d/t.toml" "title" "renamed"
    local got sect
    got="$(toml_get "$d/t.toml" title)"
    sect="$(toml_get "$d/t.toml" ui.theme)"
    rm -rf "$d"
    assert_eq "$got" "renamed"
    assert_eq "$sect" "dark"
}

#[test]
it_leaves_a_number_unquoted() {
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    toml_set "$d/t.toml" "ui.width" 42
    local line; line="$(grep '^width' "$d/t.toml" | head -1)"
    rm -rf "$d"
    assert_eq "$line" "width = 42"
}

#[test]
it_leaves_a_negative_and_a_float_unquoted() {
    local d; d="$(_tw_dir)"
    toml_set "$d/t.toml" "a.n" -12
    toml_set "$d/t.toml" "a.f" 1.5
    local n f
    n="$(grep '^n = ' "$d/t.toml")"
    f="$(grep '^f = ' "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$n" "n = -12"
    assert_eq "$f" "f = 1.5"
}

#[test]
it_leaves_a_bool_unquoted() {
    local d; d="$(_tw_dir)"
    toml_set "$d/t.toml" "a.on" true
    toml_set "$d/t.toml" "a.off" false
    local on off
    on="$(grep '^on = ' "$d/t.toml")"
    off="$(grep '^off = ' "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$on" "on = true"
    assert_eq "$off" "off = false"
}

#[test]
it_leaves_an_array_unquoted_and_readable() {
    local d; d="$(_tw_dir)"
    toml_set "$d/t.toml" "a.list" '["one", "two"]'
    local -a out=()
    toml_array "$d/t.toml" a.list out
    local n="${#out[@]}" first="${out[0]:-}"
    rm -rf "$d"
    assert_eq "$n" "2"
    assert_eq "$first" "one"
}

#[test]
it_quotes_a_string_that_looks_like_neither() {
    local d; d="$(_tw_dir)"
    toml_set "$d/t.toml" "a.v" "hello there"
    local line; line="$(grep '^v = ' "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$line" 'v = "hello there"'
}

#[test]
it_escapes_a_quote_in_the_value() {
    # Unescaped, this writes a file that no longer parses, and the next read
    # of any key in it fails for a reason nobody would connect to this write.
    local d; d="$(_tw_dir)"
    toml_set "$d/t.toml" "a.v" 'say "hi"'
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_eq "$got" 'say "hi"'
}

#[test]
it_escapes_a_backslash_in_the_value() {
    local d; d="$(_tw_dir)"
    toml_set "$d/t.toml" "a.path" 'C:\tools'
    local line; line="$(grep '^path = ' "$d/t.toml")"
    local got; got="$(toml_get "$d/t.toml" a.path)"
    rm -rf "$d"
    assert_eq "$line" 'path = "C:\\tools"'
    assert_eq "$got" 'C:\tools'
}

#[test]
it_reads_back_a_value_with_a_quote_and_a_backslash_together() {
    local d; d="$(_tw_dir)"
    toml_set "$d/t.toml" "a.v" 'a\b"c'
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_eq "$got" 'a\b"c'
}

#[test]
it_does_not_read_a_hash_after_an_escaped_quote_as_a_comment() {
    # The line cleaner counts quotes to find the end of the string. Reading an
    # escaped one as the terminator puts the rest of the value outside it, and
    # a `#` there truncates the line.
    local d; d="$(_tw_dir)"
    toml_set "$d/t.toml" "a.v" 'said "no" #1'
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_eq "$got" 'said "no" #1'
}

#[test]
it_keeps_a_hash_in_the_value_readable() {
    # The reader is quote-aware; the writer has to give it a quoted value for
    # that to help.
    local d; d="$(_tw_dir)"
    toml_set "$d/t.toml" "a.v" '#[pub]'
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_eq "$got" '#[pub]'
}

#[test]
it_survives_being_written_twice() {
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    toml_set "$d/t.toml" "ui.theme" "light"
    toml_set "$d/t.toml" "ui.theme" "dark"
    local got count
    got="$(toml_get "$d/t.toml" ui.theme)"
    count="$(grep -c '^theme = ' "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" "dark"
    assert_eq "$count" "1"
}

#[test]
it_reads_back_everything_it_wrote() {
    local d; d="$(_tw_dir)"
    toml_set "$d/t.toml" "a.one" "first"
    toml_set "$d/t.toml" "b.two" "second"
    toml_set "$d/t.toml" "a.three" "third"
    local one two three
    one="$(toml_get "$d/t.toml" a.one)"
    two="$(toml_get "$d/t.toml" b.two)"
    three="$(toml_get "$d/t.toml" a.three)"
    rm -rf "$d"
    assert_eq "$one" "first"
    assert_eq "$two" "second"
    assert_eq "$three" "third"
}

#[test]
it_refuses_a_call_with_no_key() {
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    assert_fails toml_set "$d/t.toml" "" "x"
    rm -rf "$d"
}

#[test]
it_refuses_a_call_with_no_file() {
    assert_fails toml_set "" "a.b" "x"
}

#[test]
it_leaves_no_temporary_file_beside_the_target() {
    # It writes through mktemp and renames, so a reader never sees half a
    # file. The rename has to actually happen.
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    toml_set "$d/t.toml" "ui.theme" "light"
    local n; n="$(find "$d" -type f | wc -l | tr -d ' ')"
    rm -rf "$d"
    assert_eq "$n" "1"
}

#[test]
it_removes_a_key() {
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    assert_ok toml_unset "$d/t.toml" "ui.theme"
    local gone; gone="$(toml_get "$d/t.toml" ui.theme 2>/dev/null || true)"
    local kept; kept="$(toml_get "$d/t.toml" ui.width)"
    rm -rf "$d"
    assert_empty "$gone"
    assert_eq "$kept" "30"
}

#[test]
it_removes_only_the_key_in_the_named_section() {
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    toml_unset "$d/t.toml" "net.width"
    local ui; ui="$(toml_get "$d/t.toml" ui.width)"
    local net; net="$(toml_get "$d/t.toml" net.width 2>/dev/null || true)"
    rm -rf "$d"
    assert_eq "$ui" "30"
    assert_empty "$net"
}

#[test]
it_keeps_the_comments_when_removing() {
    local d; d="$(_tw_dir)"; _tw_sample "$d/t.toml"
    toml_unset "$d/t.toml" "ui.theme"
    local body; body="$(cat "$d/t.toml")"
    rm -rf "$d"
    assert_contains "$body" "# how wide the sidebar wants to be"
    assert_contains "$body" "# a pause the writer must not close up"
}

#[test]
it_refuses_to_remove_from_a_file_that_is_not_there() {
    local d; d="$(_tw_dir)"
    assert_fails toml_unset "$d/nope.toml" "a.b"
    rm -rf "$d"
}

# --- root is a place, not the absence of one ---------------------------------
#
# Reading "no section" as "no section is open" made a root key match anywhere:
# `toml_unset f name` deleted `name` from every section in the file, and
# `toml_set f name x` rewrote the first sectioned key that happened to share
# the leaf.

#[test]
it_removes_a_root_key_without_touching_the_same_name_in_a_section() {
    local d; d="$(mktemp -d)"
    printf 'name = "root"\n[a]\nname = "x"\n[b]\nname = "y"\n' > "$d/t.toml"
    toml_unset "$d/t.toml" name
    local root a b
    root="$(toml_get "$d/t.toml" name 2>/dev/null || true)"
    a="$(toml_get "$d/t.toml" a.name)"
    b="$(toml_get "$d/t.toml" b.name)"
    rm -rf "$d"
    assert_empty "$root"
    assert_eq "$a" "x"
    assert_eq "$b" "y"
}

#[test]
it_removes_a_sectioned_key_without_touching_the_root_one() {
    # The other direction of the same law.
    local d; d="$(mktemp -d)"
    printf 'name = "root"\n[a]\nname = "x"\n[b]\nname = "y"\n' > "$d/t.toml"
    toml_unset "$d/t.toml" a.name
    local root a b
    root="$(toml_get "$d/t.toml" name)"
    a="$(toml_get "$d/t.toml" a.name 2>/dev/null || true)"
    b="$(toml_get "$d/t.toml" b.name)"
    rm -rf "$d"
    assert_eq "$root" "root"
    assert_empty "$a"
    assert_eq "$b" "y"
}

#[test]
it_writes_a_root_key_above_the_first_section() {
    # Appending it at the end of the file puts it inside whatever section ends
    # there, so the write and the read disagree about the same key.
    local d; d="$(mktemp -d)"
    printf '[a]\nname = "x"\n' > "$d/t.toml"
    toml_set "$d/t.toml" name root
    local root a first
    root="$(toml_get "$d/t.toml" name)"
    a="$(toml_get "$d/t.toml" a.name)"
    first="$(head -1 "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$root" "root"
    assert_eq "$a" "x"
    assert_eq "$first" 'name = "root"'
}

#[test]
it_appends_a_root_key_after_the_root_content_it_already_has() {
    local d; d="$(mktemp -d)"
    printf '# top\ntitle = "t"\n\n[a]\nx = 1\n' > "$d/t.toml"
    toml_set "$d/t.toml" other v
    local got line_new line_a body
    got="$(toml_get "$d/t.toml" other)"
    line_new="$(grep -n '^other' "$d/t.toml" | cut -d: -f1)"
    line_a="$(grep -n '^\[a\]' "$d/t.toml" | cut -d: -f1)"
    body="$(cat "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" "v"
    assert_ok test "$line_new" -lt "$line_a"
    assert_contains "$body" "# top"
}

#[test]
it_replaces_a_root_key_rather_than_the_sectioned_one_below_it() {
    local d; d="$(mktemp -d)"
    printf 'title = "t"\n[a]\ntitle = "inner"\n' > "$d/t.toml"
    toml_set "$d/t.toml" title new
    local root inner
    root="$(toml_get "$d/t.toml" title)"
    inner="$(toml_get "$d/t.toml" a.title)"
    rm -rf "$d"
    assert_eq "$root" "new"
    assert_eq "$inner" "inner"
}

# --- a section with nothing in it --------------------------------------------

#[test]
it_appends_into_a_section_that_is_empty() {
    # The section ends at its own header, and the header arm used to skip the
    # append, so the key landed at the end of the file inside the next section.
    local d; d="$(mktemp -d)"
    printf '[a]\n\n[b]\nx = 1\n' > "$d/t.toml"
    toml_set "$d/t.toml" a.k v
    local got wrong
    got="$(toml_get "$d/t.toml" a.k)"
    wrong="$(toml_get "$d/t.toml" b.k 2>/dev/null || true)"
    rm -rf "$d"
    assert_eq "$got" "v"
    assert_empty "$wrong"
}

#[test]
it_appends_into_an_empty_section_at_the_end_of_the_file() {
    local d; d="$(mktemp -d)"
    printf '[a]\nx = 1\n[b]\n' > "$d/t.toml"
    toml_set "$d/t.toml" b.k v
    local got
    got="$(toml_get "$d/t.toml" b.k)"
    rm -rf "$d"
    assert_eq "$got" "v"
}

# --- a value the reader can decode -------------------------------------------

#[test]
it_encodes_a_newline_rather_than_writing_one_into_the_file() {
    # An unescaped newline does not corrupt the value, it corrupts the file:
    # every key after it is on the wrong side of an unterminated string.
    local d; d="$(mktemp -d)"
    printf '[s]\nafter = 1\n' > "$d/t.toml"
    toml_set "$d/t.toml" "s.k" "$(printf 'a\nb')"
    local got after lines
    got="$(toml_get "$d/t.toml" s.k)"
    after="$(toml_get "$d/t.toml" s.after)"
    lines="$(grep -c '^k = ' "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" "$(printf 'a\nb')"
    assert_eq "$after" "1"
    assert_eq "$lines" "1"
}

#[test]
it_encodes_every_escape_the_reader_decodes() {
    # The pair has to be symmetric or the round trip is not one.
    local d; d="$(mktemp -d)"
    local want; want="$(printf 'a\tb\rc\nd')"
    toml_set "$d/t.toml" "s.k" "$want"
    local got line
    got="$(toml_get "$d/t.toml" s.k)"
    line="$(grep -c '^k = ' "$d/t.toml")"
    rm -rf "$d"
    assert_eq "$got" "$want"
    assert_eq "$line" "1"
}
