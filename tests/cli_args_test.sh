#!/usr/bin/env bash
# What the interpreter does with its own arguments.
#
# `-c` is here because every other shell takes it, so people write it, and this
# used to read it as a filename and answer `script not found: -c`. That is a
# true sentence about the wrong thing, and it sends the reader looking for a
# missing file rather than for a missing feature.

use test

nut() { "${NUT_BIN}" "$@" 2>&1; }

# Resolved once. The suite runs from the repository, and the interpreter under
# test is this checkout's rather than whichever one is on PATH.
NUT_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/nutshell"

#[test]
it_runs_a_command_given_with_dash_c() {
    assert_eq "$(nut -c 'echo hello')" "hello"
}

#[test]
it_loads_modules_in_a_dash_c_command() {
    assert_eq "$(nut -c 'use string; str_trim "  x  "')" "x"
}

# The regression this file exists for. Running the script sits outside the case
# statement precisely so that two branches can reach it; when it lived inside
# the path branch, `-c` set a script and then fell out of the case, so the
# command never ran and the exit code was zero.
#[test]
it_actually_runs_the_command_rather_than_exiting_quietly() {
    local out
    out="$(nut -c 'printf ran')"
    assert_eq "$out" "ran"
    assert_ne "$out" ""
}

#[test]
it_refuses_a_dash_c_with_nothing_after_it() {
    assert_contains "$(nut -c)" "needs a command"
    assert_exits 2 "${NUT_BIN}" -c
}

# An unknown flag is a mistake, not a filename. Reported as a file it produces a
# not-found error naming the flag, which reads as a broken path.
#[test]
it_names_an_unknown_option_as_an_option() {
    local out
    out="$(nut --no-such-flag)"
    assert_contains "$out" "unknown option"
    assert_exits 2 "${NUT_BIN}" --no-such-flag
}

#[test]
it_still_runs_an_ordinary_script_path() {
    local d out
    d="$(mktemp -d)"
    printf 'echo from-a-file\n' > "$d/s.sh"
    out="$(nut "$d/s.sh")"
    assert_eq "$out" "from-a-file"
    rm -rf "$d"
}

#[test]
it_still_says_so_when_a_script_path_is_wrong() {
    assert_contains "$(nut /no/such/script.sh)" "script not found"
}
