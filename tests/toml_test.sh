#!/usr/bin/env bash
# Tests for the TOML reader.
#
# Both of the first two pin bugs that shipped: values containing `#` were
# truncated as comments, and an array with a trailing comma reported failure
# after parsing correctly. Neither had a test, and both were found only because
# a config value happened to contain the characters that broke them.

use toml test

FIXTURE="${BASH_SOURCE[0]%/*}/fixtures/sample.toml"

#[test]
it_reads_a_plain_value() {
    assert_eq "$(toml_get "$FIXTURE" "meta.name")" "sample"
}

#[test]
it_keeps_a_hash_inside_a_quoted_value() {
    # `_toml_clean_line` truncated at the first `#` regardless of quotes, so
    # every value containing one silently became empty.
    assert_eq "$(toml_get "$FIXTURE" "annotations.public_api")" "#[pub]"
}

#[test]
it_still_strips_a_real_trailing_comment() {
    # The control: quote-awareness must not stop it stripping actual comments.
    assert_eq "$(toml_get "$FIXTURE" "meta.version")" "1.0.0"
}

#[test]
it_reads_an_array_with_a_trailing_comma() {
    # TOML permits the trailing comma. The reader populated the array and then
    # returned failure, because its last statement was a test against the empty
    # final element.
    local -a out=()
    assert_ok toml_array "$FIXTURE" "lists.with_trailing_comma" out
    assert_eq "${#out[@]}" "2"
}

#[test]
it_reads_bracket_bearing_array_values() {
    local -a out=()
    toml_array "$FIXTURE" "lists.attributes" out
    assert_eq "${out[0]}" "#[pub]"
    assert_eq "${out[1]}" "#[allow(trivial_wrapper)]"
}

#[test]
it_reports_a_missing_key_rather_than_inventing_one() {
    assert_fails toml_get "$FIXTURE" "meta.nothing_here"
}

#[test]
it_finds_a_literal_section() {
    assert_ok toml_has_section "$FIXTURE" "meta"
}

#[test]
it_finds_a_section_that_was_only_created_implicitly() {
    # `[tree.branch]` is never written. TOML v1.0.0 says `[tree.branch.leaf]`
    # creates it anyway, and `toml_subsections` already reported it as a child
    # of `tree`, so a predicate that denied it would contradict its own module.
    assert_ok toml_has_section "$FIXTURE" "tree.branch"
}

#[test]
it_denies_a_section_that_does_not_exist() {
    assert_fails toml_has_section "$FIXTURE" "tree.nope"
}

#[test]
it_does_not_match_a_section_on_a_shared_prefix() {
    # `tre` is a prefix of `tree` and is not a table.
    assert_fails toml_has_section "$FIXTURE" "tre"
}

#[test]
it_lists_direct_children_only() {
    local out; out="$(toml_subsections "$FIXTURE" "tree" | sort | tr '\n' ' ')"
    assert_eq "$out" "branch other "
}

#[test]
it_lists_a_child_once_however_many_descendants_it_has() {
    # `other` has both a literal header and a grandchild under it.
    assert_eq "$(toml_subsections "$FIXTURE" "tree.other")" "deep"
}

#[test]
it_agrees_with_itself_about_every_child_it_reports() {
    # The composition that the two functions exist to support. This is the one
    # that failed: has_section matched literal headers only, so it denied every
    # implicitly created parent that subsections had just listed.
    local child
    while IFS= read -r child; do
        assert_ok toml_has_section "$FIXTURE" "tree.$child"
    done < <(toml_subsections "$FIXTURE" "tree")
}

# --- comments inside a multi-line array ---------------------------------------

#[test]
it_drops_a_comment_line_inside_an_array() {
    # This kept the comment text, appended it into the value, and then split on
    # commas. A comment containing one swallowed the entry after it, silently,
    # and a declared path simply stopped being read.
    local d; d="$(mktemp -d)"
    cat > "$d/t.toml" <<'EOF'
[carry]
paths = [
    "one",
    # a comment, containing a comma, which is the case that broke it
    "two",
    "three",
]
EOF
    local arr=(); toml_array "$d/t.toml" carry.paths arr
    rm -rf "$d"
    assert_eq "${#arr[@]}" "3"
    assert_eq "${arr[0]}" "one"
    assert_eq "${arr[1]}" "two"
    assert_eq "${arr[2]}" "three"
}

#[test]
it_keeps_a_hash_that_is_inside_a_quoted_value() {
    # The reason the comment stripping was skipped in the first place. Both
    # have to hold: comments go, quoted hashes stay.
    local d; d="$(mktemp -d)"
    printf '[a]\nv = ["x#y", "z"]\n' > "$d/t.toml"
    local arr=(); toml_array "$d/t.toml" a.v arr
    rm -rf "$d"
    assert_eq "${arr[0]}" "x#y"
    assert_eq "${arr[1]}" "z"
}

#[test]
it_drops_a_trailing_comment_after_an_entry() {
    local d; d="$(mktemp -d)"
    cat > "$d/t.toml" <<'EOF'
[a]
v = [
    "one",   # why one
    "two",
]
EOF
    local arr=(); toml_array "$d/t.toml" a.v arr
    rm -rf "$d"
    assert_eq "${#arr[@]}" "2"
    assert_eq "${arr[0]}" "one"
}

#[test]
it_still_reads_an_array_with_no_comments_at_all() {
    # The control. A stripper that ate everything would satisfy the tests above
    # by returning nothing.
    local d; d="$(mktemp -d)"
    printf '[a]\nv = [\n  "one",\n  "two",\n]\n' > "$d/t.toml"
    local arr=(); toml_array "$d/t.toml" a.v arr
    rm -rf "$d"
    assert_eq "${#arr[@]}" "2"
}

# --- multi-line basic strings -------------------------------------------------

#[test]
it_reads_a_multiline_string() {
    # These returned a bare `"` before, which callers then used as content.
    local d; d="$(mktemp -d)"
    printf '[n]\nv = """\nline one\nline two\n"""\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" n.v)"
    rm -rf "$d"
    assert_contains "$got" "line one"
    assert_contains "$got" "line two"
}

#[test]
it_keeps_a_hash_literal_inside_a_multiline_string() {
    # Everything between the delimiters is literal. Running the comment
    # stripper over a string body truncates prose at the first `#`.
    local d; d="$(mktemp -d)"
    printf '[n]\nv = """\na # here is not a comment\n"""\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" n.v)"
    rm -rf "$d"
    assert_contains "$got" "# here is not a comment"
}

#[test]
it_reads_a_triple_quoted_value_that_closes_on_its_own_line() {
    local d; d="$(mktemp -d)"
    printf '[n]\nv = """just this"""\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" n.v)"
    rm -rf "$d"
    assert_eq "$got" "just this"
}

#[test]
it_does_not_read_a_key_out_of_a_multiline_body() {
    # The body of a string is not key-value territory. A line inside one
    # reading `keymap = fi` was returned as though it were a real setting,
    # shadowing the actual key further down the file.
    local d; d="$(mktemp -d)"
    printf '[n]\nbody = """\nkeymap = fi\n"""\nkeymap = "actually-us"\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" n.keymap)"
    rm -rf "$d"
    assert_eq "$got" "actually-us"
}

#[test]
it_finds_a_key_after_a_multiline_string() {
    # The parser has to leave the mode it entered, or everything below the
    # first multi-line value becomes unreadable.
    local d; d="$(mktemp -d)"
    printf '[n]\na = """\nsome prose\n"""\nb = "after"\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" n.b)"
    rm -rf "$d"
    assert_eq "$got" "after"
}

#[test]
it_still_reads_an_ordinary_string_beside_them() {
    # The control. None of the above is worth anything if the common case
    # regressed to make them pass.
    local d; d="$(mktemp -d)"
    printf '[n]\nm = """\nx\n"""\np = "plain"\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" n.p)"
    rm -rf "$d"
    assert_eq "$got" "plain"
}

# --- the helpers the reader leans on ------------------------------------------

#[test]
it_trims_into_a_variable_the_caller_names() {
    local v
    _toml_trim_into v "   spaced   "
    assert_eq "$v" "spaced"
}

#[test]
it_trims_into_a_variable_named_like_its_own_locals() {
    # The caller names the target, so a plain `local v` inside would shadow it
    # and hand back nothing. toml_get asks for exactly `v` and `k`, so this is
    # not hypothetical: it broke twenty-six tests at once.
    local v k line out
    _toml_trim_into v "  a  ";    assert_eq "$v" "a"
    _toml_trim_into k "  b  ";    assert_eq "$k" "b"
    _toml_clean_into line " x # c"; assert_eq "$line" "x"
    _toml_clean_into out  " y # c"; assert_eq "$out" "y"
}

#[test]
it_cleans_into_a_variable_without_forking() {
    local out
    _toml_clean_into out 'key = "value" # trailing'
    assert_eq "$out" 'key = "value"'
}

#[test]
it_keeps_a_hash_inside_quotes_when_cleaning_into_a_variable() {
    # The fork-free twin has to agree with the original on the case the
    # original exists for.
    local out
    _toml_clean_into out 'public_api = "#[pub]"'
    assert_eq "$out" 'public_api = "#[pub]"'
}

#[test]
it_agrees_with_the_printing_cleaner() {
    # Two implementations of one rule drift. Checked against each other rather
    # than against a list of cases somebody remembered.
    local samples=(
        'a = "b"'
        'a = "b" # c'
        'a = "#not a comment"'
        '# whole line'
        '   indented = 1   '
        "a = 'single #quoted'"
        ''
    )
    local s out bad=""
    for s in "${samples[@]}"; do
        _toml_clean_into out "$s"
        [[ "$out" == "$(_toml_clean_line "$s")" ]] || bad+="[$s] "
    done
    assert_empty "$bad"
}
