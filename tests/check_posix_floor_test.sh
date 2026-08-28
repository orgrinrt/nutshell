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
it_discounts_a_file_reached_only_behind_a_shell_gate() {
    local d; d="$(_pf_lib '#[shell(bash4)]
string  lib/string.sh
string  lib/string.posix.sh
other   lib/other.sh')"
    assert_eq "$(_shell_gated_files "$d")" "lib/string.sh"
    rm -rf "$d"
}

#[test]
it_counts_a_file_reached_behind_a_tool_gate() {
    # `has(bin(...))` is not `shell(...)`. A row gated on a tool is still
    # sourced on a POSIX shell wherever that tool exists, so it has to parse
    # there, and discounting it would hide a real gap.
    local d; d="$(_pf_lib '#[has(bin(grep))]
text  lib/text.fast.sh
text  lib/text.sh')"
    assert_empty "$(_shell_gated_files "$d")"
    rm -rf "$d"
}

#[test]
it_discounts_nothing_in_a_manifest_with_no_gates() {
    # The control. A matcher returning every file would empty the report and
    # read as a floor that is already reached.
    local d; d="$(_pf_lib 'one  lib/one.sh
two  lib/two.sh  internal')"
    assert_empty "$(_shell_gated_files "$d")"
    rm -rf "$d"
}

#[test]
it_does_not_carry_a_gate_past_the_row_it_applies_to() {
    # A gate attaches to the next declaration and stops. Carried on, one shell
    # gate near the top would discount every file under it and the number
    # would read as a floor already reached.
    local d; d="$(_pf_lib '#[shell(bash4)]
a  lib/a.sh
b  lib/b.sh')"
    assert_eq "$(_shell_gated_files "$d")" "lib/a.sh"
    rm -rf "$d"
}

#[test]
it_does_not_read_an_ordinary_comment_as_a_gate() {
    local d; d="$(_pf_lib '# prose about the next one
a  lib/a.sh')"
    assert_empty "$(_shell_gated_files "$d")"
    rm -rf "$d"
}

# --- the impl modules are in scope -------------------------------------------
#
# `get_script_files` honours the project's excludes, and this project excludes
# `/impl/` from its quality checks: those files are repetitive by design, one
# per tool, so a duplication or size finding about them says nothing.
#
# The POSIX question is not a quality question. An impl module is sourced at
# run time by the module that chose it, on whatever shell is running, so it has
# to parse there like anything else. Excluded, twelve of them were invisible
# and the number read as smaller than it was.

#[test]
it_scans_the_impl_modules_that_the_project_excludes() {
    local sh; sh="$(_posix_shell)" || return 0
    local files
    files="$(get_script_files)"
    # The exclusion is real, so this is what the check is working around.
    assert_eq "$(grep -c '/impl/' <<<"$files" || true)" "0"

    # And there are impl modules to find.
    local extra
    extra="$(find "$REPO_ROOT/lib" -type f -name '*.sh' -path '*/impl/*' 2>/dev/null)"
    assert_ne "$extra" ""
    assert_ok test "$(grep -c . <<<"$extra")" -gt 5
}

#[test]
it_reports_a_count_larger_than_the_excluded_scope() {
    # The property, rather than the mechanism: whatever the check scans has to
    # be more than what `get_script_files` hands it, or the widening is not
    # doing anything and the number is the old one under a new name.
    local sh; sh="$(_posix_shell)" || return 0
    local base extra
    base="$(get_script_files | grep -c . || true)"
    extra="$(find "$REPO_ROOT/lib" -type f -name '*.sh' -path '*/impl/*' 2>/dev/null | grep -c . || true)"
    assert_ok test "$extra" -gt 0
    assert_ok test "$(( base + extra ))" -gt "$base"
}

#[test]
# A module on the floor is one that RUNS there, not one that parses there.
#
# This is the distinction the check itself was missing, and it is worth an
# end-to-end test because every other test here is about the instrument. To a
# POSIX shell `[[ -n x ]]` is a command name with three arguments, so it parses
# anywhere and then reports `[[: not found`. `printf -v` is worse: it reports
# an illegal option, carries on, and leaves the variable empty.
#
# So the assertion is that `os.sh` sourced by a real POSIX shell defines its
# functions and they answer, which is the only claim that means anything.
it_runs_a_floor_module_rather_than_merely_parsing_it() {
    local sh; sh="$(_posix_shell)" || { skip "no posix shell here"; return 0; }
    local root="${BASH_SOURCE[0]%/*}/.."

    # Every function in it, not one. The first version of this called only
    # `os_name`, and putting a `[[` back into `os_is_macos` left it passing:
    # a probe that does not reach the broken line reports nothing wrong with
    # it, and the bashisms are spread one per predicate here.
    local probe='
        . "$1"/lib/os.sh || exit 1
        printf "%s|%s|" "$(os_name)" "$(os_arch)"
        os_is_linux   && printf "L" || printf "-"
        os_is_macos   && printf "M" || printf "-"
        os_is_windows && printf "W" || printf "-"
        os_is_wsl     && printf "S" || printf "-"
    '
    local got want
    got="$("$sh" -c "$probe" _ "$root" 2>&1)"
    assert_not_contains "$got" "not found"
    assert_not_contains "$got" "Bad substitution"
    assert_ne "$got" ""

    # And it agrees with the same module under bash, because a floor
    # implementation that runs and answers differently is worse than one that
    # does not run. This is what the mutation has to break.
    want="$(bash -c "$probe" _ "$root" 2>/dev/null)"
    assert_eq "$got" "$want"
}

#[test]
# `nut_once` is the quiet one, so it gets its own case.
#
# It reads `BASH_SOURCE` and uses `printf -v`. Under a POSIX shell it is not
# found, the `|| return 0` beside it returns from the whole file, and the
# module defines nothing while reporting success: the source succeeds, the
# functions are absent, and nothing says so.
#
# The check has to call that out, or a file using it reads as floor-ready and
# is not.
it_reads_nut_once_as_something_the_floor_cannot_run() {
    local f; f="$(_pf_tmp)"
    printf 'nut_once || return 0\nfoo() { echo hi; }\n' > "$f"
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_ne "$hits" "" "nut_once was not reported"
    assert_contains "$hits" "nut_once"
}

#[test]
# The control for the case above: a file with the guard the floor modules use
# instead must come back clean, or the check flags everything and says nothing.
it_reads_an_own_guard_as_fine() {
    local f; f="$(_pf_tmp)"
    printf '[ -n "${_NUTSHELL_X_SH:-}" ] && return 0\n_NUTSHELL_X_SH=1\nfoo() { echo hi; }\n' > "$f"
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_eq "$hits" ""
}

#[test]
# An unclosed `[` in a strip pattern. The one rule in the scan that catches a
# divergence rather than a refusal: `${v#[}` strips in bash and does nothing at
# all in dash, which reads the `[` as opening a bracket expression and never
# finds its `]`. Neither shell says a word, so the file passes `dash -n`, runs,
# and answers wrong.
#
# Three sites in this repo carried the bare form. One was `nut-declare` reading
# nutshell's own attribute syntax, which is how a gate name would have come
# back with the `#[` still attached.
it_reports_an_unclosed_bracket_in_a_strip_pattern() {
    local f; f="$(_pf_tmp)"
    cat > "$f" <<'BAD'
a="${v#[}"
b="${v#\#[}"
c="${v%%[}"
BAD
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_ne "$hits" "" "an unclosed bracket in a strip pattern was not reported"
}

#[test]
# The control, and it is the one that carries the rule. Both portable spellings
# and an ordinary bracket expression have to come back clean: a rule that also
# flags `${x%%[!A-Za-z0-9]*}` flags most parameter expansions in the library
# and gets switched off within a day.
it_reads_the_portable_bracket_spellings_as_fine() {
    local f; f="$(_pf_tmp)"
    cat > "$f" <<'GOOD'
a="${v#\[}"
b="${v#"["}"
c="${v%%[!A-Za-z0-9]*}"
d="${v%%[[:space:]]*}"
GOOD
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_eq "$hits" ""
}

#[test]
# The `#` spelling specifically, which is the one all three real sites used and
# the one the scan could not see at all until the comment stripper learned to
# protect a strip operator. Split from the case above because that one passes
# on its `%%` line alone, so it went green while the spelling that mattered was
# still invisible.
it_reports_an_unclosed_bracket_in_a_hash_strip_pattern() {
    local f; f="$(_pf_tmp)"
    cat > "$f" <<'BAD'
a="${v#[}"
BAD
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_ne "$hits" "" "the hash spelling was not reported"
}

#[test]
# What protecting the operator recovers, which is more than its own rule. Every
# other pattern in the scan was blind to anything sharing a line with a strip
# expansion, because the strip ate the rest of the line.
it_still_sees_a_bashism_after_a_strip_expansion_on_one_line() {
    local f; f="$(_pf_tmp)"
    cat > "$f" <<'BAD'
a="${v#foo}" ; [[ -n "$a" ]] && echo hi
BAD
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_contains "$hits" "[["
}

#[test]
# And the control: a real comment is still a comment, including one that quotes
# the very construct the rule looks for. Without this the fix could have been
# "stop stripping comments", which flags every example in every doc block.
it_still_reads_a_real_comment_as_a_comment() {
    local f; f="$(_pf_tmp)"
    cat > "$f" <<'GOOD'
a="text"   # an ordinary comment mentioning ${v#[} and [[ and $((1+1))
GOOD
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_eq "$hits" ""
}

#[test]
# A positional parameter is a variable too, and the scan could not see one.
#
# Four rules were spelled `\$\{[A-Za-z_][A-Za-z0-9_]*`, which is the grammar of
# a *name* and excludes `$1` by construction. `${1//[^:]/}` sat in a shipped
# module that the same scan reported clean, and it is fatal under dash rather
# than ignored: `Bad substitution`, at the point of use, so `dash -n` passes.
it_reports_a_bashism_on_a_positional_parameter() {
    local f; f="$(_pf_tmp)"
    cat > "$f" <<'BAD'
a="${1//[^:]/}"
b="${1,,}"
c="${2:0:3}"
BAD
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_contains "$hits" '1:'
    assert_contains "$hits" '2:'
    assert_contains "$hits" '3:'
}

#[test]
# The control: widening the name grammar must not start flagging an ordinary
# expansion. A rule that fires on `${x}` fires on every line in the library.
it_still_reads_an_ordinary_expansion_as_fine() {
    local f; f="$(_pf_tmp)"
    cat > "$f" <<'GOOD'
a="${1}"
b="${1:-default}"
c="${2%%.*}"
d="${name}/${1}"
e="$(printf '%s' "${1}")"
GOOD
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_eq "$hits" ""
}

#[test]
# `$$` before a closing quote is a process id, not an ANSI-C quote.
#
# The rule was a bare `\$'`, which matches the last two characters of
# `kill -INT $$'` and reported a trap handler in `the-whole-shebang` as a
# bashism. A false positive here costs more than a missed one: somebody goes
# looking for a construct that is not there, and the next false report gets
# assumed to be another.
it_does_not_read_a_pid_before_a_quote_as_an_ansi_c_quote() {
    local f; f="$(_pf_tmp)"
    cat > "$f" <<'GOOD'
trap 'x; kill -INT $$' INT
b="pid is $$"
GOOD
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_eq "$hits" ""
}

#[test]
# And the control: a real ANSI-C quote is still reported. Narrowing a rule
# until it stops firing is the failure this pairs against.
it_still_reports_a_real_ansi_c_quote() {
    local f; f="$(_pf_tmp)"
    cat > "$f" <<'BAD'
a=$'\033'
c=$'\t'
BAD
    local hits; hits="$(_posix_bashisms "$f")"
    rm -f "$f"
    assert_ne "$hits" "" "an ANSI-C quote was not reported"
}
