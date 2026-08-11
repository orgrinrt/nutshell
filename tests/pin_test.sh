#!/usr/bin/env bash
# Tests for the engine pin.
#
# The parser reads root-level scalars only, and stops at the first [table]
# header. That boundary is the whole point: a `nutshell_branch` written after a
# table belongs to that table, and a pin nobody reads is worse than no pin,
# because it looks like it is doing something.

use test

NUT="${BASH_SOURCE[0]%/*}/../bin/nutshell"

_pin() {
    # Exercise the parser the interpreter uses, in isolation.
    local body="$1" key="${2:-nutshell_branch}" f
    f="$(mktemp)"; printf '%s' "$body" > "$f"
    # shellcheck source=/dev/null
    ( source "$NUT" >/dev/null 2>&1; _nut_pin "$f" "$key" ) 2>/dev/null
    rm -f "$f"
}

#[test]
it_reads_a_root_level_pin() {
    assert_eq "$(_pin 'nutshell_branch = "dev"
project = "x"
')" "dev"
}

#[test]
it_reads_the_version_form_too() {
    assert_eq "$(_pin 'nutshell_version = "0.3.0"
' nutshell_version)" "0.3.0"
}

#[test]
it_ignores_a_pin_written_after_a_table_header() {
    # TOML says this key belongs to [meta], not to the document. Reading it
    # anyway would honour a pin the file does not actually declare.
    assert_eq "$(_pin '[meta]
nutshell_branch = "dev"
')" ""
}

#[test]
it_reports_no_pin_when_there_is_none() {
    assert_eq "$(_pin 'project = "x"
')" ""
}
