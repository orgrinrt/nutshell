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
