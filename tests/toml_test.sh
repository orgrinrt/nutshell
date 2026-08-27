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
it_refuses_a_target_inside_its_own_reserved_namespace() {
    # Prefixing the locals narrowed the collision to eight names rather than
    # removing it, and a write that lands on the local instead leaves the
    # caller's variable untouched with nothing to say so. Refused loudly now.
    local rc=0
    _toml_trim_into __toml_v "x" || rc=$?
    assert_ne "$rc" "0"
    rc=0
    _toml_clean_into __toml_acc "y" || rc=$?
    assert_ne "$rc" "0"
}

#[test]
it_refuses_a_target_that_is_not_a_plain_name() {
    # `printf -v` EVALUATES an array subscript, so `arr[$(cmd)]` runs the
    # command inside it. Only an identifier is accepted.
    local probe="${TMPDIR:-/tmp}/toml-target-probe.$$"
    rm -f "$probe"
    local rc=0
    _toml_trim_into "arr[\$(touch '$probe')0]" "z" 2>/dev/null || rc=$?
    local ran=0; [[ -e "$probe" ]] && ran=1
    rm -f "$probe"
    assert_eq "$ran" "0"
    assert_ne "$rc" "0"
}

#[test]
it_does_not_lose_the_second_capture_group() {
    # BASH_REMATCH is global, and any `[[ =~ ]]` between two reads of it --
    # including one inside a function called in between -- replaces it. Reading
    # group two afterwards gets nothing.
    local d; d="$(mktemp -d)"
    printf '[a]\nk = "value"\n' > "$d/t.toml"
    assert_eq "$(toml_get "$d/t.toml" a.k)" "value"
    rm -rf "$d"
}

#[test]
it_tracks_a_multiline_string_in_a_section_it_was_not_asked_about() {
    # The detection sat below the section gates, so a body in another section
    # was parsed as toml: a line reading `[n]` became a real section header and
    # `keymap = wrong` was returned as a real setting.
    local d; d="$(mktemp -d)"
    printf '[other]\nbody = """\n[n]\nkeymap = wrong\n"""\n\n[n]\nkeymap = "right"\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" n.keymap)"
    rm -rf "$d"
    assert_eq "$got" "right"
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
    # Two implementations of one rule drift. Checked against each other over
    # inputs chosen to be able to disagree -- backslashes, percent signs and a
    # leading dash all go through printf, which is where a twin diverges.
    local samples=(
        'a = "b"'
        'a = "b" # c'
        'a = "#not a comment"'
        '# whole line'
        '   indented = 1   '
        "a = 'single #quoted'"
        'a = "back\\slash"'
        'a = "100%% sure"'
        'a = "%s %d"'
        '-a = "leading dash"'
        'a = "trailing space "   # c'
        'a = "unclosed'
        'a = ""'
        ''
    )
    local s out bad=""
    for s in "${samples[@]}"; do
        _toml_clean_into out "$s"
        [[ "$out" == "$(_toml_clean_line "$s")" ]] || bad+="[$s] "
    done
    assert_empty "$bad"
}

#[test]
it_has_a_schema_that_accepts_its_own_manifest() {
    # The schema described `deps` as holding only `paths`, with
    # additionalProperties false, while nutshell's own nut.toml declares
    # `[deps.shebang]` with git and ref. The manifest failed the schema
    # shipped beside it, and nothing checked.
    local schema="${BASH_SOURCE[0]%/*}/../schemas/nut.toml.schema.json"
    local manifest="${BASH_SOURCE[0]%/*}/../nut.toml"
    assert_ok test -f "$schema"
    local names name bad=""
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        grep -q '"additionalProperties"' "$schema" || bad+="schema forbids named deps "
    done < <(grep -oE '^\[deps\.[a-z0-9_-]+\]' "$manifest" | sed 's/\[deps\.\(.*\)\]/\1/')
    assert_empty "$bad"
}

#[test]
it_reads_a_literal_multiline_string() {
    # Literal delimiters were the same bug as basic ones and were left in it:
    # the value came back as a single quote.
    #
    # The fixtures use \047 rather than a literal quote: three of those inside
    # a single-quoted shell string just toggle the quoting, and the file that
    # results is not the one the test means to write.
    local d; d="$(mktemp -d)"
    printf '[a]\nv = \047\047\047\nliteral line\n\047\047\047\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_contains "$got" "literal line"
}

#[test]
it_reads_a_single_line_literal_value() {
    local d; d="$(mktemp -d)"
    printf '[a]\nv = \047\047\047just this\047\047\047\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_eq "$got" "just this"
}

#[test]
it_does_not_close_a_literal_body_on_a_basic_delimiter() {
    # The delimiter that opened it is the one that closes it. Treating any
    # three quotes as a terminator truncates a body that quotes the other
    # kind, which prose about toml routinely does.
    local d; d="$(mktemp -d)"
    printf '[a]\nv = \047\047\047\nmentions """ here\nand ends after\n\047\047\047\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_contains "$got" "and ends after"
}

#[test]
it_decodes_an_escaped_quote_in_a_basic_string() {
    # TOML gives a basic string escapes. Handing back the backslashes means a
    # value never survives a write and a read, and every consumer that spliced
    # the result into a command got a stray backslash.
    local d; d="$(mktemp -d)"
    printf '[a]\nv = "say \\"hi\\""\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_eq "$got" 'say "hi"'
}

#[test]
it_decodes_a_backslash_and_the_named_escapes() {
    local d; d="$(mktemp -d)"
    printf '[a]\np = "C:\\\\tools"\nt = "one\\ttwo"\n' > "$d/t.toml"
    local p t
    p="$(toml_get "$d/t.toml" a.p)"
    t="$(toml_get "$d/t.toml" a.t)"
    rm -rf "$d"
    assert_eq "$p" 'C:\tools'
    assert_eq "$t" "$(printf 'one\ttwo')"
}

#[test]
it_decodes_a_unicode_escape() {
    local d; d="$(mktemp -d)"
    printf '[a]\nv = "caf\\u00e9"\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_eq "$got" "café"
}

#[test]
it_keeps_a_backslash_that_starts_no_escape() {
    # Not every backslash is an escape. Eating one that introduces nothing
    # loses a character with no warning.
    local d; d="$(mktemp -d)"
    printf '[a]\nv = "a\\qb"\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_eq "$got" 'a\qb'
}

#[test]
it_leaves_a_literal_string_exactly_as_typed() {
    # The control: a literal string has no escapes at all, so decoding one is
    # as wrong as failing to decode a basic string.
    local d; d="$(mktemp -d)"
    printf '[a]\nv = \047C:\\tools\047\n' > "$d/t.toml"
    local got; got="$(toml_get "$d/t.toml" a.v)"
    rm -rf "$d"
    assert_eq "$got" 'C:\tools'
}

#[test]
it_does_not_end_a_basic_string_at_an_escaped_quote() {
    local d; d="$(mktemp -d)"
    printf '[a]\nv = "he said \\"no\\" #1"\nw = 5\n' > "$d/t.toml"
    local v w
    v="$(toml_get "$d/t.toml" a.v)"
    w="$(toml_get "$d/t.toml" a.w)"
    rm -rf "$d"
    assert_eq "$v" 'he said "no" #1'
    assert_eq "$w" "5"
}

#[test]
it_keeps_a_hash_after_a_single_escaped_quote_on_the_hot_path() {
    # `_toml_clean_into` is the copy every value read goes through, and the
    # escaped-quote fix landed only in `_toml_clean_line`. The two cases the
    # suite had both carried an even number of escaped quotes before the `#`,
    # where the broken counting cancels out and gets the right answer by luck.
    # One is the shape that breaks.
    local d; d="$(mktemp -d)"
    printf '[a]\nv = "a \\" b # c"\nafter = 5\n' > "$d/t.toml"
    local v after
    v="$(toml_get "$d/t.toml" a.v)"
    after="$(toml_get "$d/t.toml" a.after)"
    rm -rf "$d"
    assert_eq "$v" 'a " b # c'
    assert_eq "$after" "5"
}

#[test]
it_cleans_a_line_the_same_way_through_both_cleaners() {
    # Two implementations of one rule is two places for it to be wrong, and
    # only one of them was fixed. Whatever they answer, they answer together.
    local -a cases=(
        'v = "a \" b # c"'
        'v = "a \" b \" c # d"'
        'v = "plain # hash"'
        "v = 'literal # hash'"
        'v = 1  # a real comment'
        'v = "trailing backslash \\\\"'
    )
    local c into wrong=""
    for c in "${cases[@]}"; do
        _toml_clean_into into "$c"
        [[ "$into" == "$(_toml_clean_line "$c")" ]] || wrong="${wrong} [${c}]"
    done
    assert_empty "$wrong"
}

#[test]
it_has_a_detector_that_notices_the_two_cleaners_disagreeing() {
    # The control for the comparison above: it has to be able to see a
    # difference, or its silence means nothing.
    local into
    _toml_clean_into into 'v = 1  # comment'
    assert_ne "$into" "$(_toml_clean_line 'v = 2  # comment')"
    assert_eq "$into" "$(_toml_clean_line 'v = 1  # comment')"
}

#[test]
it_reads_a_section_pair_with_an_escaped_quote_in_it() {
    # `toml_section_pairs` goes through the hot-path cleaner too.
    local d; d="$(mktemp -d)"
    printf '[a]\nv = "say \\" now"\nn = 2\n' > "$d/t.toml"
    local pairs; pairs="$(toml_section_pairs "$d/t.toml" a)"
    rm -rf "$d"
    assert_contains "$pairs" 'say " now'
    assert_contains "$pairs" "n=2"
}

#[test]
# The escape decoded under the C locale, which is the case that was broken.
#
# It used to be `printf '\uXXXX'`, and that escape is decoded against the
# current locale: under `LC_ALL=C` bash emitted the escape text unchanged, so
# a value came back as `caf\u00E9` with no error raised anywhere. A container
# and a build machine usually run the C locale, so the machines most likely to
# hit it are the ones least likely to have anyone watching.
#
# Both locales are asserted rather than only the broken one, because the fix
# has to keep the case that already worked.
it_decodes_a_unicode_escape_in_any_locale() {
    local d; d="$(mktemp -d)"
    {
        printf 'two = "caf\\u00e9"\n'
        printf 'four = "\\U0001F600"\n'
        printf 'ascii = "tab\\u0009end"\n'
    } > "$d/t.toml"

    local loc got
    for loc in C en_US.UTF-8; do
        got="$(LC_ALL="$loc" toml_get "$d/t.toml" two)"
        assert_eq "$got" "café" "two-byte codepoint under LC_ALL=${loc}"
        got="$(LC_ALL="$loc" toml_get "$d/t.toml" four)"
        assert_eq "$got" "😀" "four-byte codepoint under LC_ALL=${loc}"
        got="$(LC_ALL="$loc" toml_get "$d/t.toml" ascii)"
        assert_eq "$got" "tab	end" "one-byte codepoint under LC_ALL=${loc}"
    done
    rm -rf "$d"
}

#[test]
# What has no encoding is kept as typed rather than turned into something.
#
# A surrogate half and anything past the last codepoint are not characters,
# and a run of hex digits that is too short was never an escape. Each is left
# exactly as written, because silently producing a replacement character would
# lose the fact that the file said something impossible.
it_keeps_an_escape_that_names_no_character() {
    local d; d="$(mktemp -d)"
    {
        printf 'lone = "\\uD800"\n'
        printf 'past = "\\U00110000"\n'
        printf 'nothex = "\\uZZZZ"\n'
        printf 'short = "\\u00"\n'
    } > "$d/t.toml"

    local loc
    for loc in C en_US.UTF-8; do
        assert_eq "$(LC_ALL="$loc" toml_get "$d/t.toml" lone)" '\uD800' \
            "surrogate half under LC_ALL=${loc}"
        assert_eq "$(LC_ALL="$loc" toml_get "$d/t.toml" past)" '\U00110000' \
            "past the last codepoint under LC_ALL=${loc}"
        assert_eq "$(LC_ALL="$loc" toml_get "$d/t.toml" nothex)" '\uZZZZ' \
            "not hex under LC_ALL=${loc}"
        assert_eq "$(LC_ALL="$loc" toml_get "$d/t.toml" short)" '\u00' \
            "too few digits under LC_ALL=${loc}"
    done
    rm -rf "$d"
}
