#!/usr/bin/env bash
# Tests for the check that says the readme's two tables are the whole list.
#
# The defect it exists for is silent by construction: a table missing a row is
# never wrong, it is short, and a short table reads as complete on every
# reading. So the arms plant a table with a row taken out and assert the check
# names the one that is gone, rather than asserting it failed.
#
# `_rows_under` reads `$README`, which the check resolves once at load, so each
# arm points it at a file it wrote and puts it back.

use test

NUT_CHECK_LOAD_ONLY=1 . "${BASH_SOURCE[0]%/*}/../examples/checks/check_readme_tables.sh"

_rt_readme() { # <rows under Modules...>
    local f; f="$(mktemp "${TMPDIR:-/tmp}/nutshell-rt.XXXXXX")"
    {
        printf '### Modules\n\n| Module | What it carries |\n|---|---|\n'
        local one
        for one in "$@"; do printf '| `%s` | whatever |\n' "$one"; done
        printf '\n### Writing a module\n\nprose.\n'
    } > "$f"
    printf '%s' "$f"
}

#[test]
it_reads_the_rows_of_the_table_it_was_asked_for() {
    local was="$README"
    README="$(_rt_readme os log fs)"
    local got; got="$(_rows_under '### Modules' | tr '\n' ' ')"
    rm -f "$README"; README="$was"
    assert_eq "$got" "fs log os "
}

#[test]
it_stops_at_the_next_heading_rather_than_reading_the_file() {
    # A table further down is a different table, and reading past the heading
    # would make every check's row count as a module and hide a missing one.
    local was="$README" f
    f="$(mktemp "${TMPDIR:-/tmp}/nutshell-rt.XXXXXX")"
    {
        printf '### Modules\n\n| Module | x |\n|---|---|\n| `os` | y |\n\n'
        printf '### Checks\n\n| Check | x |\n|---|---|\n| `syntax` | y |\n'
    } > "$f"
    README="$f"
    local mods; mods="$(_rows_under '### Modules' | tr '\n' ' ')"
    local checks; checks="$(_rows_under '### Checks' | tr '\n' ' ')"
    rm -f "$f"; README="$was"
    assert_eq "$mods" "os "
    assert_eq "$checks" "syntax "
}

#[test]
it_names_the_row_that_is_missing_rather_than_counting_them() {
    local was="$README" have out
    README="$(_rt_readme os log)"
    have="$(mktemp "${TMPDIR:-/tmp}/nutshell-rt.XXXXXX")"
    printf 'fs\nlog\nos\n' > "$have"
    out="$(_table_covers modules '### Modules' "$have" 2>&1)"
    rm -f "$README" "$have"; README="$was"

    assert_contains "$out" "missing rows"
    assert_contains "$out" "fs"
    # and not the two that are there, or the report would name the whole list
    assert_not_contains "$out" "→ log"
}

#[test]
it_passes_when_the_table_names_every_one() {
    # The control. Without it every arm above would pass on a build where the
    # check fails whatever it is handed.
    #
    # Read off the counter rather than off the output: `log_pass` prints only
    # when `SHOW_PASSING` is on, so a passing verdict is silent and asserting
    # on stdout would assert nothing. The failing arm is the other way round
    # and is checked on its output above.
    local was="$README" have out before
    README="$(_rt_readme os log fs)"
    have="$(mktemp "${TMPDIR:-/tmp}/nutshell-rt.XXXXXX")"
    printf 'fs\nlog\nos\n' > "$have"
    before="${TESTS_PASSED:-0}"
    out="$(_table_covers modules '### Modules' "$have" 2>&1)"
    _table_covers modules '### Modules' "$have" >/dev/null 2>&1
    rm -f "$README" "$have"; README="$was"

    assert_eq "$out" ""
    assert_ok test "${TESTS_PASSED:-0}" -gt "$before"
    assert_eq "${TESTS_FAILED:-0}" "0"
}

#[test]
it_asks_the_tree_rather_than_a_list_written_down_here() {
    # `_modules` and `_checks` are what make the check self-maintaining, so a
    # module or a check added tomorrow is one the readme owes a row. Asserted
    # against `lib/` and the check glob rather than against names, since naming
    # them here would be the second copy this check exists to refuse.
    local mods; mods="$(_modules | wc -l | tr -d ' ')"
    local files; files="$(ls "${NUTSHELL_ROOT}/lib" | wc -l | tr -d ' ')"
    assert_ok test "$mods" -gt 0
    assert_ok test "$mods" -le "$files"

    local checks; checks="$(_checks | wc -l | tr -d ' ')"
    local globbed; globbed="$(ls "${NUTSHELL_ROOT}"/examples/checks/check_*.sh | wc -l | tr -d ' ')"
    assert_eq "$checks" "$globbed"
    assert_ok grep -qx 'readme_tables' <<< "$(_checks)"
}

