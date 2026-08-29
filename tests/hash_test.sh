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

# The digest of a known input, as a constant.
#
# `it_hashes_a_file_to_what_the_system_tool_says` compares against `_h_expect`,
# which dispatches to the same `sha256sum` or `shasum` and cuts the same field,
# so on any machine carrying one of those it compares a computation to itself.
# It still earns its place, since it catches the argument being passed wrong,
# but it cannot catch the tool being wrong and neither could anything else here.
#
# `5891b5b5...` is sha256 of the five bytes `hello\n`, and it is a fact about
# sha256 rather than about this machine.
#[test]
it_hashes_a_known_input_to_its_known_digest() {
    _h_setup
    assert_eq "$(hash_sha256 "$HROOT/f")" \
        "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
    _h_end
}

# Each arm's own output shape, parsed.
#
# The three tools disagree about where the digest sits on the line, and
# `openssl` is the one that differs: it writes `SHA256(path)= <digest>`, so the
# arm carries its own extra `${out##* }` and nothing was entering it. `_h_expect`
# has no openssl arm either, so on a machine with `sha256sum` the openssl branch
# was dead in every run this suite has ever done.
#
# Shimmed rather than skipped where a tool is absent. A skipped arm is the same
# blind spot with a nicer name, and what is being pinned here is the parse
# rather than the tool: given exactly what each writes, the right field comes
# out.
_h_stub() {
    local name="$1" line="$2"
    mkdir -p "$HROOT/bin"
    printf '#!/bin/sh\nprintf %%s\\\\n "%s"\n' "$line" > "$HROOT/bin/$name"
    chmod +x "$HROOT/bin/$name"
    PATH="$HROOT/bin:$PATH"
    # The name goes into a global rather than being closed over. Written first
    # as `hash_impl() { printf '%s' "$name"; }`, where `name` is this
    # function's own local and is long gone by the time the body runs, so every
    # arm got an empty string and fell to the `*)` case. All three assertions
    # failed at once, which is the only reason it was visible: had one of them
    # been the whole test it would have read as the tool being absent.
    _H_STUB_IMPL="$name"
    hash_impl() { printf '%s' "$_H_STUB_IMPL"; }
}

#[test]
it_parses_the_digest_out_of_each_tools_own_output_shape() {
    local want="5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
    local saved="$PATH"

    _h_setup
    _h_stub sha256sum "${want}  ${HROOT}/f"
    assert_eq "$(hash_sha256 "$HROOT/f")" "$want"
    PATH="$saved"; unset -f hash_impl; unset _H_STUB_IMPL; _h_end

    _h_setup
    _h_stub shasum "${want}  ${HROOT}/f"
    assert_eq "$(hash_sha256 "$HROOT/f")" "$want"
    PATH="$saved"; unset -f hash_impl; unset _H_STUB_IMPL; _h_end

    # The one with the prefix, and the one that was never entered.
    _h_setup
    _h_stub openssl "SHA256(${HROOT}/f)= ${want}"
    assert_eq "$(hash_sha256 "$HROOT/f")" "$want"
    PATH="$saved"; unset -f hash_impl; unset _H_STUB_IMPL; _h_end
}

# The control for the test above, so it is not three assertions that would pass
# against any implementation. A tool writing a shape no arm knows must not come
# back looking like a digest.
#[test]
it_does_not_invent_a_digest_from_a_shape_no_arm_knows() {
    local saved="$PATH" out
    _h_setup
    _h_stub openssl "no digest on this line at all"
    # The arm has to be entered for this to mean anything. A stub that never
    # ran would also produce no digest, and an earlier draft of this test
    # passed that way while all three arms above were failing.
    assert_eq "$(hash_impl)" "openssl"
    out="$(hash_sha256 "$HROOT/f" 2>/dev/null)"
    assert_ne "$out" "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
    assert_ne "${#out}" "64"
    PATH="$saved"; unset -f hash_impl; unset _H_STUB_IMPL; _h_end
}
