#!/usr/bin/env bash
# Tests for choosing a module's file before it is sourced.
#
# The half that picks between tools already existed: `text_grep` chooses `grep`
# over `perl` on first call and reloads. That is per function and inside a
# module, and it cannot help with the thing this is for.
#
# A file using a construct the running shell cannot parse fails at parse time.
# No `if` inside it can guard that, because the guard is in the file being
# parsed. So the decision has to sit above the sourcing, which is `use`, and
# that is what a `when=` row in the manifest is.
#
# Which makes the ordering load-bearing rather than cosmetic. A floor above a
# better row makes that row unreachable and nothing about the tree looks wrong.

use test

_W_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-when.XXXXXX")"
trap '[[ -n "${_W_TMP:-}" ]] && rm -rf "$_W_TMP"' EXIT

# A library root with a manifest and the files it names.
_w_lib() {
    local d; d="$(mktemp -d "${_W_TMP}/lib.XXXXXX")"
    printf '%s' "$1" > "$d/lib.nut"
    local f
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        mkdir -p "$d/${f%/*}" 2>/dev/null
        printf 'MARK=%s\n' "${f##*/}" > "$d/$f"
    done < <(awk '!/^#/ && NF>=2 {print $2}' "$d/lib.nut" | sort -u)
    printf '%s' "$d"
}

# Which file the resolver picks, as a bare name.
_w_pick() {
    local got; got="$(_lib_nut_lookup "$1" "$2" 2>/dev/null)" || return 1
    printf '%s' "${got##*/}"
}

# --- the predicate itself ----------------------------------------------------

#[test]
it_holds_for_a_command_that_is_here() {
    assert_ok _nut_when "have:sh"
}

#[test]
it_does_not_hold_for_a_command_that_is_not() {
    # The control for the one above. A predicate that always held would pass
    # every test in this file and select the first row on every machine.
    assert_fails _nut_when "have:no-such-command-anywhere-3f9a"
}

#[test]
it_holds_for_the_shell_that_is_running_this() {
    assert_ok _nut_when "shell:bash"
    assert_ok _nut_when "shell:bash4"
}

#[test]
it_reads_the_bash_floor_the_same_way_init_does() {
    # `shell:bash4` and `init`'s own guard answer one question, and two answers
    # to it is how a floor drifts. `10.0.0` is the row worth having: `1.*` is a
    # prefix of `1.` rather than of `1`.
    local v
    for v in '' 1.14.7 2.05b '3.2.57(1)-release' 4.0 '4.0.0-beta' 5.3 10.0.0; do
        local want=no
        case "$v" in ''|1.*|2.*|3.*) want=no ;; *) want=yes ;; esac
        local got=no
        BASH_VERSION="$v" _nut_when "shell:bash4" && got=yes
        assert_eq "$got" "$want" "BASH_VERSION=[$v]"
    done
}

#[test]
it_wants_both_sides_of_a_plus() {
    assert_ok    _nut_when "have:sh+have:cat"
    assert_fails _nut_when "have:sh+have:no-such-command-anywhere-3f9a"
    assert_fails _nut_when "have:no-such-command-anywhere-3f9a+have:sh"
}

#[test]
it_refuses_a_word_it_does_not_know() {
    # A typo must not read as true. Read as true, it promotes a variant onto
    # every machine, which is the exact opposite of what a predicate is for,
    # and nothing about the tree would look wrong.
    assert_fails _nut_when "hav:grep"
    assert_fails _nut_when "shell:zsh"
    assert_fails _nut_when "have:sh+wat"
}

#[test]
it_holds_for_nothing_at_all() {
    # An empty predicate is the floor, which is what a row with no `when=`
    # becomes.
    assert_ok _nut_when ""
}

#[test]
it_does_not_run_what_is_written_in_the_file() {
    # The predicate comes out of a file on disk and is never evaluated as
    # shell. `eval` here would be arbitrary execution in the one place that
    # runs before anything else in the library.
    local witness="$_W_TMP/witness"
    rm -f "$witness"
    _nut_when "env:X; touch $witness" 2>/dev/null || true
    _nut_when "have:sh; touch $witness" 2>/dev/null || true
    assert_fails test -e "$witness"
}

# --- choosing a file ---------------------------------------------------------

#[test]
it_takes_the_first_row_whose_predicate_holds() {
    local d; d="$(_w_lib 'thing  a.sh  when=have:no-such-command-anywhere-3f9a
thing  b.sh  when=have:sh
thing  c.sh')"
    assert_eq "$(_w_pick "$d" thing)" "b.sh"
}

#[test]
it_falls_to_the_row_with_no_predicate() {
    local d; d="$(_w_lib 'thing  a.sh  when=have:no-such-command-anywhere-3f9a
thing  c.sh')"
    assert_eq "$(_w_pick "$d" thing)" "c.sh"
}

#[test]
it_finds_nothing_when_no_row_holds_and_there_is_no_floor() {
    # A library with only predicated rows can fail to resolve on a machine
    # that matches none of them. That is the library's defect and the resolver
    # says so rather than picking one anyway.
    local d; d="$(_w_lib 'thing  a.sh  when=have:no-such-command-anywhere-3f9a')"
    assert_fails _w_pick "$d" thing
}

#[test]
it_reads_the_order_in_the_file_as_the_order_to_try() {
    # The same two rows the other way round. A floor above a better row makes
    # that row unreachable, and this is what says so.
    local d; d="$(_w_lib 'thing  c.sh
thing  b.sh  when=have:sh')"
    assert_eq "$(_w_pick "$d" thing)" "c.sh"
}

#[test]
it_still_resolves_a_module_that_has_no_predicate_anywhere() {
    # The control for the whole feature. Every existing manifest is rows with
    # no `when=` at all, and a change that broke those would be caught by the
    # rest of the suite, but not by anything in this file.
    local d; d="$(_w_lib 'one  one.sh
two  two.sh')"
    assert_eq "$(_w_pick "$d" one)" "one.sh"
    assert_eq "$(_w_pick "$d" two)" "two.sh"
}

#[test]
it_takes_a_visibility_and_a_predicate_on_one_row_in_either_order() {
    # Both on the same row, which is the case that was broken and which the
    # first version of this test did not reach: it used two rows, one carrying
    # each, and passed while `internal when=...` was dropping the predicate on
    # the floor and loading the module anyway.
    #
    # All four combinations, because a fix that read the words instead of the
    # positions could still have got one of them backwards.
    local d

    d="$(_w_lib 'thing  a.sh  internal when=have:no-such-command-anywhere-3f9a')"
    assert_fails _w_pick "$d" thing

    d="$(_w_lib 'thing  a.sh  when=have:no-such-command-anywhere-3f9a internal')"
    assert_fails _w_pick "$d" thing

    d="$(_w_lib 'thing  a.sh  internal when=have:sh')"
    assert_eq "$(_w_pick "$d" thing)" "a.sh"
    assert_fails _lib_nut_lookup "$d" thing public

    d="$(_w_lib 'thing  a.sh  when=have:sh internal')"
    assert_eq "$(_w_pick "$d" thing)" "a.sh"
    assert_fails _lib_nut_lookup "$d" thing public
}

#[test]
it_still_refuses_an_internal_module_from_outside() {
    # The predicate column must not have opened the visibility door. Reading a
    # trailing word and assigning it to the visibility is exactly the shape
    # that could.
    local d; d="$(_w_lib 'thing  a.sh  internal')"
    assert_fails _lib_nut_lookup "$d" thing public
    # And it is still reachable from inside, or the check above is passing for
    # the wrong reason.
    assert_eq "$(_w_pick "$d" thing)" "a.sh"
}

# --- what is remembered and what is not --------------------------------------

#[test]
it_gives_the_same_answer_for_a_binary_the_second_time() {
    # The memo, which exists because `command -v` is the only word here that
    # costs anything and this sits in front of every `use`.
    assert_ok _nut_when "have:sh"
    assert_ok _nut_when "have:sh"
    assert_fails _nut_when "have:no-such-command-anywhere-3f9a"
    assert_fails _nut_when "have:no-such-command-anywhere-3f9a"
}

#[test]
it_does_not_remember_an_answer_that_can_change() {
    # `env:` is a caller's variable and `shell:` is read from one, so neither
    # is cached. Caching them made a predicate answer once for every value it
    # was ever asked about, which is the cache being wrong rather than the
    # caller being awkward.
    export _NUT_WHEN_PROBE=1
    assert_ok _nut_when "env:_NUT_WHEN_PROBE"
    unset _NUT_WHEN_PROBE
    assert_fails _nut_when "env:_NUT_WHEN_PROBE"

    local before after
    BASH_VERSION='5.0' _nut_when "shell:bash4" && before=yes || before=no
    BASH_VERSION='3.2' _nut_when "shell:bash4" && after=yes  || after=no
    assert_eq "$before" "yes"
    assert_eq "$after"  "no"
}

#[test]
it_does_not_let_a_remembered_binary_answer_for_a_different_one() {
    # Keyed by the whole expression, not by the word. Keying by anything
    # coarser makes one answer stand for several questions.
    assert_ok    _nut_when "have:sh"
    assert_fails _nut_when "have:sh+have:no-such-command-anywhere-3f9a"
    assert_ok    _nut_when "have:sh"
}
