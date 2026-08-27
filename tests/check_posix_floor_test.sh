#!/usr/bin/env bash
# Tests for the check that says how much of this a POSIX shell can read.
#
# The floor is meant to be POSIX sh, with a `when=` row selecting a better file
# where a tool or a modern shell earns it. That is a direction rather than a
# state, so it needs a number that moves.
#
# The instrument is the part worth testing. Written against `sh` it reports a
# clean floor on a library that has none, because `sh` on macOS is bash in
# POSIX mode and accepts arrays, `[[` and here-strings. The first measurement
# taken here was exactly that and was worthless, so the shell it picks is
# verified against a probe rather than trusted by name.

use test

NUT_CHECK_LOAD_ONLY=1 . "${BASH_SOURCE[0]%/*}/../examples/checks/check_posix_floor.sh"

_pf_tmp() { mktemp "${TMPDIR:-/tmp}/nutshell-pf.XXXXXX"; }

#[test]
it_finds_a_shell_that_is_actually_posix() {
    local sh; sh="$(_posix_shell)" || { assert_eq "no posix shell here" "skipped"; return 0; }
    assert_ne "$sh" ""
    assert_ok command -v "$sh"
}

#[test]
it_refuses_a_named_shell_that_accepts_an_array() {
    # The control that makes every number this check prints mean anything, and
    # it has to be driven rather than observed: with `dash` on the machine the
    # selection returns `dash` first whatever the probes do, so asserting
    # properties of what came back tests dash and not the choosing.
    #
    # `POSIX_SHELL` goes to the front of the candidate list, so naming `bash`
    # asks the probes to reject the shell they exist to reject. Written the
    # other way first, and removing both probes killed nothing.
    POSIX_SHELL="bash"
    local got; got="$(_posix_shell)" || got=""
    POSIX_SHELL=""
    assert_ne "$got" "bash"
}

#[test]
it_refuses_the_sh_on_this_machine_when_that_sh_is_bash() {
    # The specific trap, named. `sh` here is bash 3.2 in POSIX mode and takes
    # arrays, `[[` and here-strings, so a check written against it reports a
    # clean floor on a library that has none.
    local probe; probe="$(_pf_tmp)"
    printf 'a=(1 2)\n' > "$probe"
    if sh -n "$probe" >/dev/null 2>&1; then
        # This machine's `sh` is not POSIX enough, so the selection must not
        # return it even when asked for it by name.
        POSIX_SHELL="sh"
        local got; got="$(_posix_shell)" || got=""
        POSIX_SHELL=""
        assert_ne "$got" "sh"
    else
        # Somewhere whose `sh` really is POSIX. Then it is a legitimate answer
        # and the assertion is that it is reachable rather than excluded.
        POSIX_SHELL="sh"
        assert_eq "$(_posix_shell)" "sh"
        POSIX_SHELL=""
    fi
    rm -f "$probe"
}

#[test]
it_refuses_a_named_shell_that_cannot_read_ordinary_posix() {
    # The other half of the probe. Without it the selection would take
    # anything that merely rejects arrays, including something that rejects
    # everything, and the library would read as entirely unreadable.
    local fake; fake="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-pf.XXXXXX")"
    printf '#!/bin/sh\nexit 1\n' > "$fake/refuses-all"
    chmod +x "$fake/refuses-all"

    POSIX_SHELL="$fake/refuses-all"
    local got; got="$(PATH="$fake:$PATH" _posix_shell)" || got=""
    POSIX_SHELL=""
    assert_ne "$got" "$fake/refuses-all"
    rm -rf "$fake"
}

#[test]
it_reads_a_bashism_as_unreadable_and_plain_posix_as_readable() {
    # End to end on two files whose answers are known, because everything
    # above is about the shell and nothing yet about the reading.
    local sh; sh="$(_posix_shell)" || return 0
    local bad good
    bad="$(_pf_tmp)";  printf 'a=(1 2)\necho "${a[0]}"\n' > "$bad"
    good="$(_pf_tmp)"; printf 'x=1\necho "${x}"\n' > "$good"

    assert_fails "$sh" -n "$bad"
    assert_ok    "$sh" -n "$good"
    rm -f "$bad" "$good"
}

#[test]
it_matches_an_exempt_pattern_and_not_a_neighbour() {
    POSIX_EXEMPT=('lib/legacy/*.sh' 'lib/one.sh')
    assert_ok    _is_exempt "lib/legacy/thing.sh"
    assert_ok    _is_exempt "lib/one.sh"
    assert_fails _is_exempt "lib/two.sh"
    assert_fails _is_exempt "lib/legacy.sh"
    POSIX_EXEMPT=()
}

#[test]
it_exempts_nothing_when_nothing_is_configured() {
    # The control for the one above. An exemption matcher that said yes to
    # everything would empty the report and read as a clean floor.
    POSIX_EXEMPT=()
    assert_fails _is_exempt "lib/anything.sh"
    assert_fails _is_exempt ""
}

# --- a file behind a shell predicate is not counted --------------------------
#
# The question is which modules a POSIX shell cannot load, not which files it
# cannot parse. Those stopped being the same thing the moment a module could
# carry a variant: the bash file of a module with a floor will never parse
# under dash and never has to.
#
# Counting it makes the number go up when a floor is added, which is the number
# moving the wrong way while the library gets better.

_pf_lib() {
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-pf.XXXXXX")"
    printf '%s' "$1" > "$d/lib.nut"
    printf '%s' "$d"
}

#[test]
it_discounts_a_file_reached_only_behind_a_shell_predicate() {
    local d; d="$(_pf_lib 'string  lib/string.sh        when=shell:bash4
string  lib/string.posix.sh
other   lib/other.sh')"
    local got; got="$(_shell_gated_files "$d")"
    assert_eq "$got" "lib/string.sh"
    rm -rf "$d"
}

#[test]
it_counts_a_file_reached_behind_a_tool_predicate() {
    # `have:` is not `shell:`. A row predicated on a tool is still sourced on a
    # POSIX shell wherever that tool exists, so it has to parse there, and
    # discounting it would hide a real gap.
    local d; d="$(_pf_lib 'text  lib/text.fast.sh  when=have:grep
text  lib/text.sh')"
    assert_empty "$(_shell_gated_files "$d")"
    rm -rf "$d"
}

#[test]
it_discounts_nothing_in_a_manifest_with_no_predicates() {
    # The control. A matcher that returned every file would empty the report
    # and read as a floor that is already reached.
    local d; d="$(_pf_lib 'one  lib/one.sh
two  lib/two.sh  internal')"
    assert_empty "$(_shell_gated_files "$d")"
    rm -rf "$d"
}

#[test]
it_reads_a_shell_predicate_written_after_a_visibility() {
    # The trailing columns are words, not positions, and this reader has to
    # agree with the resolver about that or the two disagree about which file
    # a POSIX shell ever sees.
    local d; d="$(_pf_lib 'a  lib/a.sh  internal when=shell:bash4
b  lib/b.sh  when=shell:bash internal')"
    local got; got="$(_shell_gated_files "$d")"
    assert_contains "$got" "lib/a.sh"
    assert_contains "$got" "lib/b.sh"
    rm -rf "$d"
}
