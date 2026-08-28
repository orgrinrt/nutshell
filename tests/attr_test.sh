#!/usr/bin/env bash
# Tests for the attribute reader.

use attr test

FIXTURE="${BASH_SOURCE[0]%/*}/fixtures/attributed.sh"

#[test]
it_finds_an_attribute_on_a_definition() {
    assert_ok attr_has "$FIXTURE" marked_fn pub
}

#[test]
it_does_not_invent_one_that_is_absent() {
    # The control. Every other assertion here would hold for a reader that
    # answered yes to everything.
    assert_fails attr_has "$FIXTURE" plain_fn pub
}

#[test]
it_reads_across_an_intervening_doc_comment() {
    # Attributes sit above the prose, not glued to the definition, so a reader
    # that stopped at the first comment would work only on undocumented code.
    assert_ok attr_has "$FIXTURE" documented_fn pub
}

#[test]
it_reads_the_argument() {
    assert_eq "$(attr_arg "$FIXTURE" limited_fn allow)" "loc = 400"
}

#[test]
it_reads_a_scoped_visibility() {
    assert_eq "$(attr_arg "$FIXTURE" internal_fn pub)" "lib"
}

#[test]
it_does_not_carry_an_attribute_past_real_code() {
    # A marker followed by a statement belongs to nothing. Carrying it onward
    # would silently mark whatever came next.
    assert_fails attr_has "$FIXTURE" after_code_fn pub
}

#[test]
it_finds_every_definition_with_a_given_attribute() {
    assert_eq "$(attr_find "$FIXTURE" test | tr '\n' ' ')" "a_test_fn b_test_fn "
}

#[test]
it_tells_two_arguments_of_one_attribute_apart() {
    # `#[allow(trivial_wrapper)]` and `#[allow(loc = 400)]` are not the same
    # marker. Matching on the name alone would let a size exemption excuse a
    # wrapper, which is the check the argument exists to scope.
    assert_eq "$(attr_arg "$FIXTURE" wrapper_allowed allow)" "trivial_wrapper"
    assert_eq "$(attr_arg "$FIXTURE" big_but_allowed allow)" "loc = 400"
}

# --- what this module needs on the machine ------------------------------------
#
# Nothing. It reads comments, and it used to do that by piping every line of
# the file through `sed`, once per line, per lookup. On a library of 36 files
# and 440 functions that was a quarter of a million processes and it made the
# QA gate take four minutes.
#
# Bash can match a line itself. That is both the fast answer and the portable
# one: a module this low should not need a userland to answer a question about
# a comment, and a rescue console may not have one.

#[test]
it_calls_no_external_tool_at_all() {
    local src="${BASH_SOURCE[0]%/*}/../lib/attr.sh"
    local stray
    # Code lines only. The comments above talk about the tools this no longer
    # uses, and saying so is the point of them.
    stray="$(grep -nE '(^|[^[:alnum:]_#])(awk|sed|grep|cut|head|tail|tr|wc|sort|expr)[[:space:]]' "$src" \
        | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
    assert_empty "$stray"
}

#[test]
it_spawns_nothing_while_walking_a_file() {
    # The property behind the one above, measured rather than read. A command
    # substitution is a fork too, so this catches the shape that was actually
    # slow: `$(_attr_defines "$line")` per line.
    local src="${BASH_SOURCE[0]%/*}/../lib/attr.sh"
    local body
    body="$(sed -n '/^attr_on() {/,/^}/p' "$src"; sed -n '/^attr_find() {/,/^}/p' "$src")"

    # Both walkers, counted. The first guard here asserted the extraction was
    # non-empty, which closes the case where both are renamed and leaves the
    # one that matters: rename `attr_on` alone, keep a wrapper, and put a fork
    # in its loop, and `attr_find`'s text alone satisfies "non-empty" and
    # "contains a read loop" while the forking walker is never looked at.
    #
    # A zero out of a pipeline is a claim about the pipeline, and so is a one
    # where two were meant.
    assert_ne "$body" ""
    local loops; loops="$(grep -c 'while IFS= read -r line' <<<"$body")"
    assert_eq "$loops" "2" "both walkers have to be in the extraction"

    # No `$(...)` inside either walker. `$(( ))` is arithmetic and is not one.
    local subs; subs="$(grep -n '\$(' <<<"$body" | grep -v '\$((' || true)"
    assert_empty "$subs"
}

#[test]
it_still_reads_an_attribute_with_an_argument_out_of_a_real_file() {
    # The control for both above: taking the tools out has to leave the
    # answers alone, including the tab-separated argument form.
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-attr.XXXXXX")"
    printf '#[pub]\n#[allow(loc = 400)]\n# prose does not break the run\n\nbig_fn() {\n  :\n}\n' \
        > "$d/x.sh"
    assert_ok  attr_has "$d/x.sh" big_fn pub
    assert_ok  attr_has "$d/x.sh" big_fn allow
    assert_fails attr_has "$d/x.sh" big_fn nope
    assert_eq "$(attr_arg "$d/x.sh" big_fn allow)" "loc = 400"
    assert_empty "$(attr_arg "$d/x.sh" big_fn pub)"
    assert_eq "$(attr_find "$d/x.sh" pub)" "big_fn"
    rm -rf "$d"
}

# --- one answer about what a definition is ------------------------------------
#
# bash accepts several spellings and this module took one of them, so a
# `#[pub]` on any of the others was invisible and the public-API check skipped
# those functions in silence rather than reporting them undocumented.
#
# `srcfile` had its own pattern for the same question and the two had already
# drifted: this one took no hyphen and no `function` keyword, that one took
# both. They share `ATTR_DEFINES_PATTERN` now.

_ad_file() {
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-defines.XXXXXX")"
    cat > "$d/f.sh" <<'EOS'
#[pub]
function old_style {
  :
}
#[pub]
function with_parens() {
  :
}
#[pub]
spaced_paren ()
{
  :
}
#[pub]
has-hyphen() { :; }
#[pub]
plain() { :; }
not_marked() { :; }
EOS
    printf '%s' "$d"
}

#[test]
it_reads_every_spelling_bash_accepts_for_a_definition() {
    local d; d="$(_ad_file)"
    local n
    for n in old_style with_parens spaced_paren has-hyphen plain; do
        assert_ok attr_has "$d/f.sh" "$n" pub
    done
    rm -rf "$d"
}

#[test]
it_finds_all_of_them_and_not_the_unmarked_one() {
    local d; d="$(_ad_file)"
    local found; found="$(attr_find "$d/f.sh" pub | sort | tr '\n' ' ')"
    assert_contains "$found" "old_style"
    assert_contains "$found" "with_parens"
    assert_contains "$found" "spaced_paren"
    assert_contains "$found" "has-hyphen"
    assert_contains "$found" "plain"
    # The control: a function with no attribute is not swept up by widening
    # what counts as a definition.
    assert_fails grep -q 'not_marked' <<<"$found"
    rm -rf "$d"
}

#[test]
it_gives_the_same_answer_as_srcfile_for_every_line() {
    # The divergence, as its own case. Two readers of one question have to
    # agree, and these two did not.
    use srcfile
    local d; d="$(_ad_file)"
    nut_load_file "$d/f.sh"
    local n
    for n in old_style with_parens spaced_paren has-hyphen plain; do
        assert_ok attr_has "$d/f.sh" "$n" pub
        assert_ok nut_defined_at "$d/f.sh" "$n"
    done
    rm -rf "$d"
}

#[test]
it_says_nothing_for_a_line_that_defines_nothing() {
    assert_fails attr_defines_on 'x=1'
    assert_fails attr_defines_on '# plain() { :; }'
    assert_fails attr_defines_on ''
    assert_fails attr_defines_on '  if foo(); then'
    assert_eq "$(attr_defines_on 'plain() { :; }')" "plain"
    assert_eq "$(attr_defines_on 'function old_style {')" "old_style"
}

# --- the POSIX floor ---------------------------------------------------------

_at_posix_sh() {
    local cand probe; probe="$(mktemp)"
    for cand in dash ash yash posh sh; do
        command -v "$cand" >/dev/null 2>&1 || continue
        printf 'a=(1 2)\n' > "$probe"
        "$cand" -n "$probe" >/dev/null 2>&1 && continue
        printf 'x=1\necho "${x:-}"\n' > "$probe"
        "$cand" -n "$probe" >/dev/null 2>&1 && { rm -f "$probe"; printf '%s' "$cand"; return 0; }
    done
    rm -f "$probe"; return 1
}

# Everything the module answers, under one shell, as one string.
_at_answers() {
    "$1" -c '
        use() { return 0; }
        . "$1/lib/attr.sh" >/dev/null 2>&1
        printf "on=[%s]"      "$(attr_on "$1/lib/string.sh" str_trim | tr "\n" ",")"
        attr_has "$1/lib/string.sh" str_trim pub && printf "has=1" || printf "has=0"
        printf "<find=%s>"    "$(attr_find "$1/lib/attr.sh" pub | wc -l | tr -d " ")"
        printf "<tests=%s>"   "$(attr_find "$1/tests/attr_test.sh" test | wc -l | tr -d " ")"
        printf "def=[%s|%s|%s|%s]" \
            "$(attr_defines_on "foo() {")" \
            "$(attr_defines_on "function bar {")" \
            "$(attr_defines_on "  baz ()")" \
            "$(attr_defines_on "not a definition")"
        printf "arg=[%s]"     "$(attr_arg "$1/lib/attr.sh" attr_on allow)"
        # Every function called, so a bashism in one that the calls above do
        # not reach still shows up.
        for f in $(grep -oE "^[a-z_][a-zA-Z0-9_]*\(\)" "$1/lib/attr.sh" | sed "s/()//" | sort -u); do
            printf "%s=" "$f"
            "$f" x y z >/dev/null 2>&1 && printf "1;" || printf "0;"
        done
    ' _ "$2" 2>&1
}

#[test]
# It parses there, which everything below depends on.
it_reads_under_a_posix_shell() {
    local sh; sh="$(_at_posix_sh)"
    assert_ne "$sh" ""
    assert_ok "$sh" -n "${BASH_SOURCE[0]%/*}/../lib/attr.sh"
}

#[test]
# Every function in the module, called under a POSIX shell, against bash.
#
# The function list is read out of the file rather than written here. A hand
# list covers what somebody thought to name, and in `validate.sh` the three it
# missed were the three that were broken: `${val,,}` is fatal when it runs and
# invisible when it parses, so a parse check said the file was fine.
#
# This module was regexes throughout, so the conversion touched every path in
# it. Answering the same is the only evidence that none of them moved.
it_answers_the_same_under_both_shells() {
    local sh root; sh="$(_at_posix_sh)"
    root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
    local p b
    b="$(_at_answers bash "$root")"
    p="$(_at_answers "$sh" "$root")"
    assert_not_contains "$p" "Bad substitution"
    assert_not_contains "$p" "not found"
    assert_ne "$b" ""
    assert_eq "$p" "$b"
}

#[test]
# And it answers correctly, not merely identically.
#
# The control for the test above. Two shells running a module that defined
# nothing agree perfectly, which is exactly how the `nut_once` guard hid itself
# in two other modules: the answers matched because both were empty.
it_answers_correctly_under_a_posix_shell() {
    local sh root; sh="$(_at_posix_sh)"
    root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
    local got; got="$(_at_answers "$sh" "$root")"
    assert_contains "$got" "on=[pub,]"
    assert_contains "$got" "has=1"
    # Both spellings of a definition, a leading-space one, and a line that is
    # not a definition at all.
    assert_contains "$got" "def=[foo|bar|baz|]"
    # And it found some, rather than nothing. Delimited, because the function
    # roll-call below prints `attr_find=0;` and a bare `find=0` matches inside
    # it: the first version of this assertion failed on a correct run.
    assert_not_contains "$got" "<find=0>"
    assert_not_contains "$got" "<tests=0>"
}
