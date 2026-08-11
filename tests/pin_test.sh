#!/usr/bin/env bash
# Tests for the engine pin.
#
# The first version of this file tested the parser and nothing else, and every
# real defect was somewhere else: a refresh that never refreshed, a guard that
# disabled itself in nested calls, a ref handed to git as an option. Review
# found twenty-one. So the parser tests stay and the rest of the file is about
# the things that actually broke.
#
# Note the shape of the helper below. Sourcing bin/nutshell to reach its
# functions is only safe because the sourced-guard sits above the pin block; in
# the first version it sat below, so this very file could exec itself away the
# moment nutshell's own nut.toml carried a pin.

use test

NUT="${BASH_SOURCE[0]%/*}/../bin/nutshell"

_pin() {
    local body="$1" key="${2:-nutshell_branch}" f
    f="$(mktemp)"; printf '%s' "$body" > "$f"
    ( source "$NUT" >/dev/null 2>&1; _nut_pin "$f" "$key" ) 2>/dev/null
    rm -f "$f"
}

_ref_ok() { ( source "$NUT" >/dev/null 2>&1; _nut_ref_ok "$1" ); }

# --- the parser -------------------------------------------------------------

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

#[test]
it_reads_a_pin_on_a_final_line_with_no_newline() {
    # `while read` drops a trailing partial line, so this returned nothing.
    # Every fixture in the first version of this file ended in a newline, which
    # is exactly why the bug survived having tests.
    assert_eq "$(_pin 'nutshell_branch = "dev"')" "dev"
}

#[test]
it_treats_an_empty_value_as_no_pin() {
    # An empty value used to succeed, which short-circuited the version
    # fallback: a broken branch line plus a good version line resolved to no
    # pin at all rather than to the version.
    assert_eq "$(_pin 'nutshell_branch = ""
nutshell_version = "0.2.0"
')" ""
    assert_eq "$(_pin 'nutshell_branch = ""
nutshell_version = "0.2.0"
' nutshell_version)" "0.2.0"
}

# --- the ref, which reaches git ---------------------------------------------

#[test]
it_accepts_ordinary_refs() {
    assert_ok _ref_ok "dev"
    assert_ok _ref_ok "main"
    assert_ok _ref_ok "0.2.0"
    assert_ok _ref_ok "release/1.2"
}

#[test]
it_refuses_a_ref_that_git_would_read_as_an_option() {
    # `--upload-pack=touch /tmp/pwned` was passed positionally with no `--`
    # and executed against a path or file:// remote. Validated rather than
    # escaped: the set of legitimate ref names is small and known.
    assert_fails _ref_ok "--upload-pack=touch /tmp/pwned"
    assert_fails _ref_ok "-x"
}

#[test]
it_refuses_refs_git_itself_rejects() {
    assert_fails _ref_ok "bad..ref"
    assert_fails _ref_ok "trailing.lock"
    assert_fails _ref_ok "has space"
    assert_fails _ref_ok ""
}

# --- staleness --------------------------------------------------------------

#[test]
it_reports_a_fetchless_mirror_as_due() {
    local d; d="$(mktemp -d)"; mkdir -p "$d/.git"
    assert_eq "$( ( source "$NUT" >/dev/null 2>&1; _nut_age "$d" ) )" "3600"
    rm -rf "$d"
}

#[test]
it_treats_a_clock_that_moved_backwards_as_due() {
    # A future stamp gave a negative age, so the mirror parked until
    # wall-clock caught up rather than refreshing.
    local d; d="$(mktemp -d)"; mkdir -p "$d/.git"
    touch -t 203001010000 "$d/.git/FETCH_HEAD"
    assert_eq "$( ( source "$NUT" >/dev/null 2>&1; _nut_age "$d" ) )" "3600"
    rm -rf "$d"
}

#[test]
it_reports_a_fresh_mirror_as_young() {
    local d age; d="$(mktemp -d)"; mkdir -p "$d/.git"
    touch "$d/.git/FETCH_HEAD"
    age="$( ( source "$NUT" >/dev/null 2>&1; _nut_age "$d" ) )"
    assert_ok bash -c "[[ '$age' =~ ^[0-9]+$ ]] && (( $age < 60 ))"
    rm -rf "$d"
}

# --- the manifest walk ------------------------------------------------------

#[test]
it_stops_the_manifest_walk_at_a_repository_boundary() {
    # The unbounded walk reached /tmp on macOS, where anyone can plant a
    # nut.toml and choose which engine another user's scripts run.
    local root; root="$(mktemp -d)"
    printf 'nutshell_branch = "planted"\n' > "$root/nut.toml"
    mkdir -p "$root/proj/sub"; mkdir -p "$root/proj/.git"
    assert_fails bash -c "source '$NUT' >/dev/null 2>&1; _nut_manifest '$root/proj/sub'"
    rm -rf "$root"
}

#[test]
it_finds_a_manifest_the_script_actually_belongs_to() {
    local root; root="$(mktemp -d)"
    mkdir -p "$root/proj/sub"
    printf 'nutshell_branch = "dev"\n' > "$root/proj/nut.toml"
    assert_eq "$(bash -c "source '$NUT' >/dev/null 2>&1; _nut_manifest '$root/proj/sub'")" \
              "$root/proj/nut.toml"
    rm -rf "$root"
}
