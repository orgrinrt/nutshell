#!/usr/bin/env bash
# Tests for `array.sh`, which had none.
#
# The module is a public surface with, at the time these were written, no
# callers anywhere in the tree and no tests. Both halves of that are worth
# knowing: untested is why the conversion to the POSIX floor could not be done
# safely without writing these first, and uncalled is a question for whoever
# decides what the library ships.

use test
use array

# Build a named list. It took a name and then pushed into a hardcoded one,
# which worked only because every call passed that same name, and the test for
# leaving a second list alone had to build its second list by hand to get round
# it.
_l() {
    local name="$1"; shift 2>/dev/null || true
    list_new "$name"
    local v; for v in "$@"; do list_push "$name" "$v"; done
}
_dump() { local s; list_ref s "$1"; printf '%s' "$s" | tr '\037' '|'; }

#[test]
it_finds_an_element_among_the_arguments() {
    assert_ok    arr_contains b a b c
    assert_ok    arr_contains a a b c
    assert_ok    arr_contains c a b c
    assert_fails arr_contains z a b c
    assert_fails arr_contains "" a b c
    assert_fails arr_contains b
    # An element that is a prefix or a suffix of another is not that other one.
    assert_fails arr_contains ab abc
    assert_fails arr_contains bc abc
    # Spaces and globs are compared literally, not matched.
    assert_ok    arr_contains "a b" "a b" c
    assert_fails arr_contains "*" a b
    assert_ok    arr_contains "*" "*" b
}

#[test]
it_reports_where_an_element_sits_and_255_when_it_is_absent() {
    assert_eq "$(arr_index a a b c)" "0"
    assert_eq "$(arr_index b a b c)" "1"
    assert_eq "$(arr_index c a b c)" "2"
    assert_eq "$(arr_index z a b c)" "255"
    assert_fails arr_index z a b c
    assert_ok    arr_index a a b c
    # The first of a repeat, not the last.
    assert_eq "$(arr_index b a b c b)" "1"
}

#[test]
it_answers_the_trivial_questions_about_the_arguments() {
    assert_eq "$(arr_length a b c)" "3"
    assert_eq "$(arr_length)" "0"
    assert_eq "$(arr_length "")" "1"
    assert_ok    arr_is_empty
    assert_fails arr_is_empty a
    assert_fails arr_is_empty ""
    assert_eq "$(arr_first a b c)" "a"
    assert_eq "$(arr_last a b c)" "c"
    assert_eq "$(arr_first only)" "only"
    assert_eq "$(arr_last only)" "only"
    assert_fails arr_last
    # `arr_last` walks rather than using bash's `${!#}`, so a value with
    # spaces has to survive the walk.
    assert_eq "$(arr_last a "b c")" "b c"
}

#[test]
it_filters_the_arguments_by_a_glob() {
    assert_eq "$(arr_filter 'a*' apple bat avocado | tr '\n' ' ')" "apple avocado "
    assert_eq "$(arr_filter '*t' apple bat | tr '\n' ' ')" "bat "
    assert_eq "$(arr_filter 'z*' apple bat)" ""
    assert_eq "$(arr_filter '*' a b | tr '\n' ' ')" "a b "
    # The pattern is a glob and the elements are not: an element holding `*`
    # is matched literally by a literal pattern.
    assert_eq "$(arr_filter '?' a bb | tr '\n' ' ')" "a "
}

#[test]
it_drops_repeats_and_keeps_the_first_of_each() {
    _l _t_l b a b c a
    arr_unique _t_l
    assert_eq "$(_dump _t_l)" "b|a|c|"

    _l _t_l
    arr_unique _t_l
    assert_eq "$(list_len _t_l)" "0"

    _l _t_l only
    arr_unique _t_l
    assert_eq "$(_dump _t_l)" "only|"

    _l _t_l same same same
    arr_unique _t_l
    assert_eq "$(_dump _t_l)" "same|"

    # The seen-set is a string, so an element that is a substring of another
    # must not count as already seen. This is the defect that shape invites.
    _l _t_l ab a b
    arr_unique _t_l
    assert_eq "$(_dump _t_l)" "ab|a|b|"

    _l _t_l "a b" a b
    arr_unique _t_l
    assert_eq "$(_dump _t_l)" "a b|a|b|"

    # An empty element is an element, and there is only one of it.
    _l _t_l "" a ""
    arr_unique _t_l
    assert_eq "$(_dump _t_l)" "|a|"
}

#[test]
it_reverses_a_list() {
    _l _t_l a b c
    arr_reverse _t_l
    assert_eq "$(_dump _t_l)" "c|b|a|"

    _l _t_l a b
    arr_reverse _t_l
    assert_eq "$(_dump _t_l)" "b|a|"

    _l _t_l only
    arr_reverse _t_l
    assert_eq "$(_dump _t_l)" "only|"

    _l _t_l
    arr_reverse _t_l
    assert_eq "$(list_len _t_l)" "0"

    # Twice is where it started.
    _l _t_l a "b c" d
    arr_reverse _t_l; arr_reverse _t_l
    assert_eq "$(_dump _t_l)" "a|b c|d|"
}

#[test]
it_sorts_a_list() {
    _l _t_l c a b
    assert_ok arr_sort _t_l
    assert_eq "$(_dump _t_l)" "a|b|c|"

    _l _t_l b a
    arr_sort _t_l
    assert_eq "$(_dump _t_l)" "a|b|"

    _l _t_l only
    assert_ok arr_sort _t_l
    assert_eq "$(_dump _t_l)" "only|"

    _l _t_l
    assert_ok arr_sort _t_l
    assert_eq "$(list_len _t_l)" "0"

    # Lexicographic, which is what `sort` does and not what a number would.
    _l _t_l 10 9 1
    arr_sort _t_l
    assert_eq "$(_dump _t_l)" "1|10|9|"

    # An element with a space survives the trip through the file.
    _l _t_l "b b" "a a"
    arr_sort _t_l
    assert_eq "$(_dump _t_l)" "a a|b b|"
}

#[test]
it_refuses_to_sort_a_list_holding_a_newline_and_leaves_it_alone() {
    # An element with a newline cannot go through `sort` at all: it would come
    # back as two. Refusing beats losing one silently, and the list has to
    # survive the refusal rather than being half-rewritten.
    _l _t_l "one
two" zzz
    local before; before="$(_dump _t_l)"
    arr_sort _t_l
    assert_eq "$?" "2"
    assert_eq "$(_dump _t_l)" "$before"
}

#[test]
it_leaves_a_second_list_alone() {
    # All three of these build their answer in a scratch list and copy it back.
    # A scratch list that leaked, or a copy that wrote to the wrong name, shows
    # up here and nowhere else.
    _l _t_l c a b
    _l _t_other keep
    arr_sort _t_l
    assert_eq "$(_dump _t_other)" "keep|"
    arr_unique _t_l
    assert_eq "$(_dump _t_other)" "keep|"
    arr_reverse _t_l
    assert_eq "$(_dump _t_other)" "keep|"
}

#[test]
it_refuses_a_name_that_is_not_a_started_list() {
    # These three used to take a bash array through a nameref. That call shape
    # now names a list that does not exist, and without a check it would report
    # success and leave the array untouched, which is the worst outcome for a
    # consumer upgrading: silent, and rc 0.
    local fn
    for fn in arr_unique arr_reverse arr_sort; do
        assert_fails "$fn" never_started_list
        assert_fails "$fn" ""
    done

    # A bash array by name, which is exactly the old call shape.
    local -a fruits=(apple banana apple)
    assert_fails arr_unique fruits
    assert_eq "${fruits[*]}" "apple banana apple"

    # An empty list is a started list and is accepted.
    list_new _t_empty
    assert_ok arr_sort _t_empty
    assert_ok arr_unique _t_empty
    assert_ok arr_reverse _t_empty
}

#[test]
it_has_no_scratch_list_for_a_caller_to_collide_with() {
    # The scratch was a hardcoded global, so a list called that was emptied and
    # the call returned zero. Deriving it from the caller's name moved the
    # collision rather than removing it: a caller holding `_arrtmp_x` was still
    # emptied when somebody sorted `x`, and the test named for the defect
    # picked a victim that could never collide, so it passed against it.
    #
    # There is no scratch list now. The answer is built in a local string, so
    # there is no name for a caller to hold. This checks the property that
    # replaced it: nothing outside the list under operation is touched, and the
    # reserved space is not reachable as a name at all.
    assert_fails list_new _arrtmp_anything
    assert_fails list_new _arrtmp__t_l
    assert_fails list_new _NUT_LIST_N_x

    # The shape that used to be eaten, as close as a caller can now get.
    _l _t_l c a b a
    _l arrtmp__t_l KEEP1 KEEP2
    assert_ok arr_unique _t_l
    assert_eq "$(_dump arrtmp__t_l)" "KEEP1|KEEP2|"
    assert_eq "$(_dump _t_l)" "c|a|b|"

    # And every other list in reach stays as it was, through all three.
    _l _t_l c a b
    _l _t_other keep
    arr_sort _t_l;    assert_eq "$(_dump _t_other)" "keep|"
    arr_unique _t_l;  assert_eq "$(_dump _t_other)" "keep|"
    arr_reverse _t_l; assert_eq "$(_dump _t_other)" "keep|"
}
