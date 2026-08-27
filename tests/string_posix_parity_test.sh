#!/usr/bin/env bash
# Tests that the POSIX string floor answers what the bash one answers.
#
# Two files with one surface is only safe while they agree, and agreement is
# not something you can establish by reading them side by side: the bash one
# uses `${x,,}`, `${x//}` and `${x:i:n}`, and the POSIX one uses `tr`, a cut
# loop and `cut -c`, so nothing about them looks alike.
#
# So both are driven over the same inputs and the answers are compared. The
# POSIX one is run under a real POSIX shell rather than under bash, because
# running it under bash tests nothing that the bash file does not already
# cover, and the interesting failures are the ones bash forgives.
#
# `str_split` is absent from the floor on purpose and is not compared here.
# It writes into an array through a nameref, POSIX has neither, and a version
# returning some other shape would be a different function wearing the same
# name.

use test

ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
BASHFILE="$ROOT/lib/string.sh"
POSIXFILE="$ROOT/lib/string.posix.sh"

# A POSIX shell that is one, or nothing. Same probe the floor check uses: it
# must reject an array and still accept ordinary POSIX.
_sp_shell() {
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

# What the bash file answers, under bash.
#
# `nut_once` is stubbed rather than nutshell loaded, because loading nutshell
# would also load `string` through the manifest and the point is to run one
# named file. Written without the stub, every call came back 127 and the
# comparison was between two absences.
_ask_bash() {
    bash -c 'nut_once() { return 0; }
             . "$1" >/dev/null 2>&1; shift; f="$1"; shift
             command -v "$f" >/dev/null 2>&1 || { printf "|missing"; exit 0; }
             "$f" "$@"; printf "|%s" "$?"' \
        _ "$BASHFILE" "$@" 2>/dev/null
}

# What the POSIX file answers, under a POSIX shell.
_ask_posix() {
    local sh="$1"; shift
    "$sh" -c 'nut_once() { return 0; }
              . "$1" >/dev/null 2>&1; shift; f="$1"; shift
              command -v "$f" >/dev/null 2>&1 || { printf "|missing"; exit 0; }
              "$f" "$@"; printf "|%s" "$?"' \
        _ "$POSIXFILE" "$@" 2>/dev/null
}

# Both, compared. The status is part of the answer: three of these return a
# verdict rather than text and comparing only stdout would call them all equal.
_same() {
    local sh="$1"; shift
    local b p
    b="$(_ask_bash "$@")"
    p="$(_ask_posix "$sh" "$@")"
    assert_eq "$p" "$b" "$*"
}

#[test]
it_has_a_posix_shell_to_compare_under() {
    # The control for every test below. Without a POSIX shell they all skip,
    # and a skip that reports a pass is how a parity suite comes to mean
    # nothing.
    local sh; sh="$(_sp_shell)"
    assert_ne "$sh" ""
    assert_ne "$sh" "bash"
}

#[test]
it_reads_the_floor_under_a_posix_shell_at_all() {
    # And the control for that: the file has to load there. This is the whole
    # reason the floor exists, so it is asserted rather than assumed.
    local sh; sh="$(_sp_shell)" || return 0
    assert_ok "$sh" -n "$POSIXFILE"
    assert_fails "$sh" -n "$BASHFILE"
}

#[test]
it_answers_the_same_for_case_and_trimming() {
    local sh; sh="$(_sp_shell)" || return 0
    _same "$sh" str_lower "HeLLo WoRLD"
    _same "$sh" str_lower ""
    _same "$sh" str_upper "hello world"
    _same "$sh" str_upper "ALREADY"
    _same "$sh" str_trim "   padded   "
    _same "$sh" str_trim "none"
    _same "$sh" str_trim "   "
    _same "$sh" str_trim ""
    _same "$sh" str_ltrim "   left"
    _same "$sh" str_rtrim "right   "
    _same "$sh" str_trim "$(printf '\tmixed \t')"
}

#[test]
it_answers_the_same_for_replace() {
    local sh; sh="$(_sp_shell)" || return 0
    _same "$sh" str_replace "hello world" "world" "bash"
    _same "$sh" str_replace "aaa" "a" "b"
    _same "$sh" str_replace "aaa" "aa" "b"
    _same "$sh" str_replace "nothing here" "zzz" "x"
    _same "$sh" str_replace "keep" "" "x"
    _same "$sh" str_replace "" "a" "b"
    # A needle with regex characters in it, which is why this is a loop rather
    # than a `sed`: a caller's needle is a literal.
    _same "$sh" str_replace "a.b.c" "." "-"
    _same "$sh" str_replace 'a*b' '*' '+'
    _same "$sh" str_replace 'a[b]c' '[b]' 'X'
    # Removing rather than replacing.
    _same "$sh" str_replace "xxhixx" "xx" ""
}

#[test]
it_answers_the_same_for_the_three_that_return_a_verdict() {
    local sh; sh="$(_sp_shell)" || return 0
    _same "$sh" str_contains "hello world" "world"
    _same "$sh" str_contains "hello world" "zzz"
    _same "$sh" str_contains "hello" ""
    _same "$sh" str_starts_with "hello world" "hello"
    _same "$sh" str_starts_with "hello world" "world"
    _same "$sh" str_starts_with "hello" ""
    _same "$sh" str_ends_with "hello world" "world"
    _same "$sh" str_ends_with "hello world" "hello"
    _same "$sh" str_ends_with "hello" ""
    # A needle that is a glob, which `case` would match as a pattern if the
    # quoting were wrong on either side.
    _same "$sh" str_contains "a*b" "*"
    _same "$sh" str_starts_with "abc" "a*"
}

#[test]
it_answers_the_same_for_join_length_substr_and_repeat() {
    local sh; sh="$(_sp_shell)" || return 0
    _same "$sh" str_join ", " a b c
    _same "$sh" str_join ", " a
    _same "$sh" str_join ", "
    _same "$sh" str_join "" a b
    _same "$sh" str_length "hello"
    _same "$sh" str_length ""
    _same "$sh" str_substr "hello world" 0 5
    _same "$sh" str_substr "hello world" 6
    _same "$sh" str_substr "hello world" 6 5
    _same "$sh" str_substr "hello" 0
    _same "$sh" str_repeat "-" 5
    _same "$sh" str_repeat "ab" 3
    _same "$sh" str_repeat "-" 0
    _same "$sh" str_repeat "-" -1
}

#[test]
it_answers_the_same_distance() {
    local sh; sh="$(_sp_shell)" || return 0
    _same "$sh" str_distance build buidl
    _same "$sh" str_distance "" ""
    _same "$sh" str_distance abc ""
    _same "$sh" str_distance "" abc
    _same "$sh" str_distance same same
    _same "$sh" str_distance kitten sitting
    _same "$sh" str_distance a b
}

#[test]
it_does_not_define_split_on_the_floor() {
    # Absent on purpose. A caller wanting it wants bash, and finds out by the
    # name not being there rather than by getting an answer in the wrong shape.
    local sh; sh="$(_sp_shell)" || return 0
    local out
    out="$("$sh" -c 'nut_once() { return 0; }; . "$1" >/dev/null 2>&1; command -v str_split >/dev/null && echo THERE || echo absent' _ "$POSIXFILE" 2>&1)"
    assert_eq "$out" "absent"

    # And the control: it is there in the bash one, so the line above is about
    # the floor rather than about the name being wrong.
    out="$(bash -c 'nut_once() { return 0; }; . "$1" >/dev/null 2>&1; command -v str_split >/dev/null && echo there || echo ABSENT' _ "$BASHFILE" 2>&1)"
    assert_eq "$out" "there"
}
