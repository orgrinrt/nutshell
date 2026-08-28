#!/usr/bin/env bash
# Tests for the colour module, and for `color_wrap` in particular.
#
# `color_wrap` takes the *name* of a variable and reads it indirectly, which is
# the one thing in this module that was bash-only in a way nothing caught: the
# file parsed under a POSIX shell, so it counted as being on the floor, while
# every call returned the empty string and the shell carried on at exit zero.

use color test

# A POSIX shell to check against, or nothing. `sh` on macOS is bash in POSIX
# mode and would pass everything here without proving anything.
_ct_posix_sh() {
    local cand f; f="$(mktemp)"
    printf 'declare -A x\n' > "$f"
    for cand in dash ash yash busybox-sh; do
        command -v "$cand" >/dev/null 2>&1 || continue
        if ! "$cand" -c ". '$f'" >/dev/null 2>&1; then
            rm -f "$f"; printf '%s' "$cand"; return 0
        fi
    done
    rm -f "$f"; return 1
}

#[test]
it_wraps_text_in_the_named_colour() {
    local RED; RED="$(printf '\033[31m')"
    local NC; NC="$(printf '\033[0m')"
    assert_eq "$(color_wrap RED "Err")" "${RED}Err${NC}"
}

#[test]
# An unset name gives the text back rather than an empty string, which is what
# a caller relies on when colour is off.
it_returns_the_text_when_the_name_names_nothing() {
    assert_eq "$(color_wrap _CT_NO_SUCH_VAR "plain")" "plain"
}

#[test]
# The name reaches an `eval`, so it is checked first. Without that,
# `color_wrap 'X}; echo PWNED; :' t` is a command rather than a lookup.
it_does_not_execute_what_a_caller_puts_in_the_name() {
    local out
    out="$(color_wrap 'X}; echo PWNED; :' "t" 2>&1)"
    assert_not_contains "$out" "PWNED"
    assert_eq "$out" "t"

    out="$(color_wrap '$(echo PWNED2)' "t" 2>&1)"
    assert_not_contains "$out" "PWNED2"
}

#[test]
# The case that shipped: it parsed under a POSIX shell and did not work there.
#
# `${!name}` is bash's indirect expansion and a fatal `Bad substitution`
# elsewhere. Asserted against the shell rather than against a pattern, because
# the failure was that the answer differed between shells while both exited
# zero.
it_wraps_the_same_way_under_a_posix_shell() {
    local sh; sh="$(_ct_posix_sh)" || { skip "no strict POSIX shell here"; return 0; }
    local root="${BASH_SOURCE[0]%/*}/.."

    local probe='
        RED=$(printf "\033[31m"); NC=$(printf "\033[0m")
        . "$1"/lib/color.sh 2>/dev/null
        color_wrap RED "Err"
    '
    local got want
    got="$("$sh" -c "$probe" _ "$root" 2>&1)"
    want="$(bash -c "$probe" _ "$root" 2>&1)"

    assert_not_contains "$got" "Bad substitution"
    assert_ne "$got" ""
    assert_eq "$got" "$want"
}
