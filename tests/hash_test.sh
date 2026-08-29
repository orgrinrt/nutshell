#!/usr/bin/env bash
# Tests for digests and for reading somebody's list of them.
#
# The thing worth pinning is the exit codes. "There is nothing here that can
# hash" and "that file is not readable" are different facts, one about the
# machine and one about the argument, and a caller that collapses them reports
# "I could not check" as "it did not match". Comparing two digests is not here
# and is not this library's job: that is an application, and applications live
# a layer up.

use test
use hash

_h_setup() { HROOT="$(mktemp -d)"; printf 'hello\n' > "$HROOT/f"; mkdir -p "$HROOT/empty"; }
_h_end()   { rm -rf "$HROOT"; unset HROOT; }

# What this machine says, so the expected value is not a constant this test
# would have to be right about on every platform.
_h_expect() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1
    else shasum -a 256 < "$1" | cut -d' ' -f1; fi
}

#[test]
it_hashes_a_file_to_what_the_system_tool_says() {
    _h_setup
    assert_eq "$(hash_sha256 "$HROOT/f")" "$(_h_expect "$HROOT/f")"
    _h_end
}

#[test]
it_gives_a_lowercase_hex_digest_of_the_right_length() {
    _h_setup
    local d; d="$(hash_sha256 "$HROOT/f")"
    assert_eq "${#d}" "64"
    assert_eq "$d" "$(printf '%s' "$d" | tr 'A-F' 'a-f')"
    _h_end
}

#[test]
it_separates_an_unreadable_file_from_a_machine_that_cannot_hash() {
    # The whole reason this returns three things. 1 is about the argument, 2 is
    # about the machine, and a caller that cannot tell them apart cannot decide
    # what to do about either.
    _h_setup
    hash_sha256 "$HROOT/nosuch" 2>/dev/null; assert_eq "$?" "1"
    local saved="$PATH"; PATH="$HROOT/empty"
    hash_sha256 "$HROOT/f" 2>/dev/null; assert_eq "$?" "2"
    PATH="$saved"
    _h_end
}

#[test]
it_names_a_tool_when_there_is_one_and_none_when_there_is_not() {
    _h_setup
    assert_ne "$(hash_impl)" ""
    local saved="$PATH"; PATH="$HROOT/empty"
    assert_eq "$(hash_impl)" ""
    PATH="$saved"
    _h_end
}

#[test]
it_wants_a_path() {
    assert_fails hash_sha256 ""
}

#[test]
it_reads_a_digest_out_of_a_sums_file() {
    _h_setup
    printf 'aaaa  one.tar.gz\nbbbb  two.zip\n' > "$HROOT/SUMS"
    assert_eq "$(hash_sums_get "$HROOT/SUMS" two.zip)" "bbbb"
    _h_end
}

#[test]
it_reads_the_binary_mode_form_too() {
    # `sha256sum -b` writes a star before the name, both forms are published in
    # the wild, and splitting on a fixed separator gets one of them wrong.
    _h_setup
    printf 'cccc *bin.zip\n' > "$HROOT/SUMS"
    assert_eq "$(hash_sums_get "$HROOT/SUMS" bin.zip)" "cccc"
    _h_end
}

#[test]
it_does_not_match_a_name_that_is_merely_a_suffix() {
    # `kanata.zip` must not answer for `nata.zip`, which is what matching off
    # the end of the line with a glob would have done.
    _h_setup
    printf 'dddd  kanata.zip\n' > "$HROOT/SUMS"
    assert_fails hash_sums_get "$HROOT/SUMS" nata.zip
    assert_fails hash_sums_get "$HROOT/SUMS" anata.zip
    assert_eq    "$(hash_sums_get "$HROOT/SUMS" kanata.zip)" "dddd"
    _h_end
}

#[test]
an_unlisted_name_is_an_absence_rather_than_an_error() {
    # A sums file covering three of four published files is ordinary, and the
    # fourth is unlisted rather than wrong.
    _h_setup
    printf 'eeee  one.zip\n' > "$HROOT/SUMS"
    local out; out="$(hash_sums_get "$HROOT/SUMS" other.zip 2>&1)"
    assert_fails hash_sums_get "$HROOT/SUMS" other.zip
    assert_empty "$out"
    _h_end
}

#[test]
it_skips_blank_lines_and_comments() {
    _h_setup
    printf '# a header\n\nffff  one.zip\n' > "$HROOT/SUMS"
    assert_eq "$(hash_sums_get "$HROOT/SUMS" one.zip)" "ffff"
    _h_end
}

#[test]
it_reads_a_list_off_stdin_as_well_as_off_a_file() {
    # The shape a caller has when the list arrived over the network and was
    # never written down.
    _h_setup
    assert_eq "$(printf 'gggg  a.zip\nhhhh  b.zip\n' | hash_sums_pick b.zip)" "hhhh"
    assert_empty "$(printf 'gggg  a.zip\n' | hash_sums_pick c.zip)"
    _h_end
}

#[test]
it_reads_a_file_with_no_trailing_newline() {
    # A `read` loop drops the last line without the `|| [ -n "$line" ]` guard,
    # and a sums file with no final newline is a real thing.
    _h_setup
    printf 'iiii  last.zip' > "$HROOT/SUMS"
    assert_eq "$(hash_sums_get "$HROOT/SUMS" last.zip)" "iiii"
    _h_end
}

#[test]
it_wants_both_a_file_and_a_name() {
    _h_setup
    assert_fails hash_sums_get "" one.zip
    assert_fails hash_sums_get "$HROOT/SUMS" ""
    assert_fails hash_sums_get "$HROOT/nosuch" one.zip
    _h_end
}

#[test]
the_digest_it_reads_back_is_the_digest_it_wrote() {
    # End to end, so the two halves cannot drift into disagreeing about the
    # shape of a line.
    _h_setup
    local d; d="$(hash_sha256 "$HROOT/f")"
    printf '%s  f\n' "$d" > "$HROOT/SUMS"
    assert_eq "$(hash_sums_get "$HROOT/SUMS" f)" "$d"
    _h_end
}
