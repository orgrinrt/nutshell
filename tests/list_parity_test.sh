#!/usr/bin/env bash
# Tests that the POSIX list answers what the bash one answers.
#
# One keeps a string and lets the shell field-split it; the other keeps an
# associative array with the index in the key. They look nothing alike, so
# reading them side by side establishes nothing and this drives both over the
# same operations instead, the floor under a real POSIX shell rather than under
# bash, which forgives too much to be a test.
#
# The awkward elements are the point. A value with spaces, one with a newline,
# and one holding `*` and `?` all break a naive split: `IFS` left at its
# default splits the first two, and `set -f` left off turns the third into a
# directory listing. Every case below carries at least one of them.

use test

ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
POSIXFILE="$ROOT/lib/list.sh"
BASHFILE="$ROOT/lib/list.bash.sh"

_lp_shell() {
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

_both() {
    local sh="$1" body="$2" b p
    b="$(bash -c 'nut_once() { return 0; }; . "$1" || exit 1; shift; eval "$1"' _ "$BASHFILE" "$body" 2>&1)"
    p="$("$sh" -c 'nut_once() { return 0; }; . "$1" || exit 1; shift; eval "$1"' _ "$POSIXFILE" "$body" 2>&1)"
    assert_eq "$p" "$b" "$body"
}

#[test]
it_has_a_posix_shell_to_compare_under() {
    # The positive control. Every case below returns early without a POSIX
    # shell, and a skip that reports a pass is how a parity suite comes to mean
    # nothing.
    local sh; sh="$(_lp_shell)"
    assert_ne "$sh" ""
    assert_ne "$sh" "bash"
}

#[test]
it_reads_the_floor_under_a_posix_shell_and_the_other_does_not() {
    local sh; sh="$(_lp_shell)" || return 0
    assert_ok "$sh" -n "$POSIXFILE"
    assert_fails "$sh" -n "$BASHFILE"
}

#[test]
it_answers_the_same_for_push_and_length() {
    local sh; sh="$(_lp_shell)" || return 0
    _both "$sh" 'list_new a; list_len a'
    _both "$sh" 'list_new a; list_push a x; list_push a y; list_len a'
    _both "$sh" 'list_new a; list_push a ""; list_len a'
    _both "$sh" 'list_new a; list_push a x; list_new a; list_len a'
}

#[test]
it_answers_the_same_for_elements_that_break_a_naive_split() {
    # Spaces need IFS pinned to the separator, `*` and `?` need set -f, and a
    # newline needs both. An implementation getting any of them wrong reports a
    # different length or a different element and the case fails on that.
    local sh; sh="$(_lp_shell)" || return 0
    _both "$sh" 'list_new a; list_push a "a value with spaces"; printf "%s|%s" "$(list_len a)" "$(list_get a 0)"'
    _both "$sh" 'list_new a; list_push a "star * and ? here"; printf "%s|%s" "$(list_len a)" "$(list_get a 0)"'
    _both "$sh" 'list_new a; list_push a "one
two"; printf "%s|%s" "$(list_len a)" "$(list_get a 0)"'
    _both "$sh" 'list_new a; list_push a "tab	here"; printf "%s|%s" "$(list_len a)" "$(list_get a 0)"'
    _both "$sh" 'list_new a; list_push a "*"; list_push a "?"; list_push a "[a-z]"; printf "%s|%s|%s|%s" "$(list_len a)" "$(list_get a 0)" "$(list_get a 1)" "$(list_get a 2)"'
}

#[test]
it_answers_the_same_for_get_and_read_and_the_edges() {
    local sh; sh="$(_lp_shell)" || return 0
    _both "$sh" 'list_new a; list_push a x; list_push a y; list_push a z; printf "%s|%s|%s" "$(list_get a 0)" "$(list_get a 1)" "$(list_get a 2)"'
    _both "$sh" 'list_new a; list_push a x; list_get a 5; printf "|%s" "$?"'
    _both "$sh" 'list_new a; list_push a x; list_read v a 5; printf "%s|%s" "$?" "$v"'
    _both "$sh" 'list_new a; list_push a x; list_read v a 0; printf "%s|%s" "$?" "$v"'
    _both "$sh" 'list_new a; list_get a 0; printf "|%s" "$?"'
}

#[test]
it_refuses_a_value_holding_the_separator_on_both() {
    # A value one half takes and the other rejects is worse than a limit both
    # hold to, so the bash half refuses it too even though nothing there would
    # mangle on it.
    local sh; sh="$(_lp_shell)" || return 0
    _both "$sh" 'list_new a; list_push a "bad${LIST_SEP}x"; printf "%s|%s" "$?" "$(list_len a)"'
    _both "$sh" 'list_new a; list_push a ok; list_push a "bad${LIST_SEP}x"; printf "%s|%s|%s" "$?" "$(list_len a)" "$(list_get a 0)"'
}

#[test]
it_walks_in_order_on_both() {
    local sh; sh="$(_lp_shell)" || return 0
    _both "$sh" 'show() { printf "[%s]" "$1"; }; list_new a; list_push a x; list_push a "a b"; list_push a "*"; list_each a show'
    _both "$sh" 'show() { printf "[%s]" "$1"; }; list_new a; list_each a show; printf "|%s" "$?"'
    _both "$sh" 'stop() { [ "$1" = y ] && return 3; printf "[%s]" "$1"; }; list_new a; list_push a x; list_push a y; list_push a z; list_each a stop; printf "|%s" "$?"'
}

#[test]
it_gives_the_callee_the_shell_as_it_found_it() {
    # `list_each` sets IFS and `set -f` to walk, and has to put both back
    # before calling. A callee that word-splits an unquoted expansion would
    # otherwise split on the separator, and a callee that globs would not.
    # That defect only shows for callers who happen to do those things, which
    # is why it is pinned here rather than left to notice.
    local sh; sh="$(_lp_shell)" || return 0
    _both "$sh" 'splitty() { set -- $1; printf "<%s>" "$#"; }; list_new a; list_push a "a b c d"; list_each a splitty'
    _both "$sh" 'globby() { set -- $1; printf "<%s>" "$#"; }; list_new a; list_push a "a b"; list_each a globby'
}

#[test]
it_gives_the_same_raw_string_from_both() {
    # A caller that walks `list_str` itself must get the same bytes whichever
    # half is loaded, or it has to ask which one it got.
    local sh; sh="$(_lp_shell)" || return 0
    _both "$sh" 'list_new a; list_push a x; list_push a "a b"; list_str a | od -An -c | tr -s " "'
    _both "$sh" 'list_new a; list_str a | od -An -c | tr -s " "'
}

#[test]
it_keeps_two_lists_apart() {
    local sh; sh="$(_lp_shell)" || return 0
    _both "$sh" 'list_new one; list_new two; list_push one a; list_push two b; printf "%s|%s|%s|%s" "$(list_len one)" "$(list_len two)" "$(list_get one 0)" "$(list_get two 0)"'
    _both "$sh" 'list_new one; list_new two; list_push one a; list_new two; printf "%s|%s" "$(list_len one)" "$(list_get one 0)"'
}
