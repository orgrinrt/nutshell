#!/usr/bin/env bash
# Tests for a failing check saying what it found.
#
# The runner sets `NUTSHELL_CHECK_QUIET=1` so eight checks do not each print a
# summary block. A check that fails then prints nothing at all, and the runner
# showed a bare red cross with no thread to pull. Observed on a consumer whose
# gate went from green to failing the moment it started reading the right
# repository, with nothing on screen to say why.

use test

_CRP_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-checkrep.XXXXXX")"
trap '[[ -n "${_CRP_TMP:-}" ]] && rm -rf "$_CRP_TMP"' EXIT
_CRP_NUT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

# A project whose only check is one we wrote, so what the runner does with a
# child's output is the only thing under test.
_crp_project() {
    local name="$1" body="$2"
    local d="$_CRP_TMP/$name"
    mkdir -p "$d/checks"
    printf '[qa]\ncustom_checks = ["checks/probe.sh"]\nrun_builtins = false\n' > "$d/nut.toml"
    printf '#!/usr/bin/env bash\n%s\n' "$body" > "$d/checks/probe.sh"
    chmod +x "$d/checks/probe.sh"
    printf '%s' "$d"
}

_crp_run() { (cd "$1" && "$_CRP_NUT/check" 2>&1); }

#[test]
it_shows_what_a_check_found_when_the_check_prints_it() {
    local d; d="$(_crp_project talks '
printf "✗ the thing is wrong\n"
exit 1')"
    local out; out="$(_crp_run "$d")"
    assert_contains "$out" "the thing is wrong"
}

#[test]
it_asks_a_silent_failing_check_again_with_its_report_turned_on() {
    # The case. Quiet on the first run, and the reader is left with a cross.
    local d; d="$(_crp_project quiet '
if [[ "${NUTSHELL_CHECK_QUIET:-0}" == "1" ]]; then exit 1; fi
printf "✗ four wrappers are trivial\n"
exit 1')"
    local out; out="$(_crp_run "$d")"
    assert_contains "$out" "four wrappers are trivial"
}

#[test]
it_says_so_when_a_check_fails_and_will_not_explain_itself_either_way() {
    # A check that says nothing however it is asked. The runner cannot invent
    # a reason, and printing nothing at all is what it used to do.
    local d; d="$(_crp_project mute 'exit 1')"
    local out; out="$(_crp_run "$d")"
    assert_contains "$out" "failed and printed nothing"
}

#[test]
it_does_not_ask_again_when_the_check_passed() {
    # The second run costs a whole check. It happens on failure only, and a
    # check that ran twice would say so here.
    local d; d="$(_crp_project counted '
printf "%s\n" "ran" >> "$PWD/ran.log"
exit 0')"
    _crp_run "$d" >/dev/null
    assert_eq "$(grep -c . "$d/ran.log" 2>/dev/null || printf 0)" "1"
}

# --- the verdict is an exit code, not a glyph in the output --------------------
#
# `exit_with_status` promised "2 on warnings only" in its own usage line and
# had two branches that never returned 2. So the only way the runner could tell
# a warning from a clean pass was to grep tens of kilobytes of the child's
# stdout for the character it prints, which needs quiet mode to have left the
# line in and needs whichever `grep` is installed to read the pattern the same
# way. A check reporting 23 warnings came out as a clean pass.

#[test]
it_reports_warnings_through_the_exit_code() {
    local d; d="$(_crp_project warned '
. "'"$_CRP_NUT"'/init"
use check-runner
log_warn_test() { :; }
TESTS_WARNED=1
exit_with_status')"
    local out; out="$(_crp_run "$d")"
    assert_contains "$out" "⚠"
    assert_fails grep -q '✓ probe' <<<"$out"
}

#[test]
it_reports_a_clean_run_as_clean() {
    local d; d="$(_crp_project clean '
. "'"$_CRP_NUT"'/init"
use check-runner
exit_with_status')"
    local out; out="$(_crp_run "$d")"
    assert_fails grep -q '⚠' <<<"$out"
}

#[test]
it_still_reads_the_glyph_from_a_check_that_cannot_say_two() {
    # A custom check that does not use the framework has no `exit_with_status`
    # to call, so the fallback stays.
    local d; d="$(_crp_project glyphonly '
printf "  ⚠ something wants a look\n"
exit 0')"
    local out; out="$(_crp_run "$d")"
    assert_contains "$out" "⚠"
}

#[test]
it_does_not_ask_a_warning_to_explain_itself() {
    # Re-running is for a failure that said nothing. A warning is not a
    # failure, and asking cost a whole second run of the check.
    local d; d="$(_crp_project quietwarn '
. "'"$_CRP_NUT"'/init"
use check-runner
printf "%s\n" "ran" >> "$PWD/ran.log"
TESTS_WARNED=1
exit_with_status')"
    _crp_run "$d" >/dev/null
    assert_eq "$(grep -c . "$d/ran.log" 2>/dev/null || printf 0)" "1"
}


# --- a check sourced into this process must not inherit it ---------------------
#
# The runner sources a check with the nutshell shebang into a subshell rather
# than starting eight interpreters. All eight built-in checks take that branch
# and every fixture in this file used `#!/usr/bin/env bash`, so the branch that
# runs in production had no coverage at all.

# A project whose check carries the nutshell shebang, which is the branch the
# built-in checks take.
_crp_nut_project() {
    local name="$1" body="$2"
    local d="$_CRP_TMP/$name"
    mkdir -p "$d/checks"
    printf '[qa]\ncustom_checks = ["checks/probe.sh"]\nrun_builtins = false\n' > "$d/nut.toml"
    printf '#!/usr/bin/env nutshell\n%s\n' "$body" > "$d/checks/probe.sh"
    chmod +x "$d/checks/probe.sh"
    printf '%s' "$d"
}

#[test]
it_gives_a_sourced_check_no_arguments_of_its_own() {
    local d; d="$(_crp_nut_project args '
if [[ $# -ne 0 ]]; then
    printf "  ✗ inherited %s argument(s): %s\n" "$#" "$*"
    exit 1
fi
exit 0')"
    local out; out="$(_crp_run "$d")"
    # It used to get the runner's `$1` and `$2`: the check path and its display
    # name. Any check reading `$1` or `$@` was operating on itself.
    assert_fails grep -q 'inherited' <<<"$out"
    assert_contains "$out" "✓"
}

#[test]
it_runs_a_sourced_check_at_all() {
    # The control for the one above: the nutshell-shebang branch is genuinely
    # taken and its exit code is genuinely read.
    local d; d="$(_crp_nut_project taken '
printf "  ✗ this check ran and failed on purpose\n"
exit 1')"
    local out; out="$(_crp_run "$d")"
    assert_contains "$out" "ran and failed on purpose"
}

#[test]
it_reports_a_sourced_checks_warnings_through_its_exit_code() {
    local d; d="$(_crp_nut_project warned '
use check-runner
TESTS_WARNED=1
exit_with_status')"
    local out; out="$(_crp_run "$d")"
    assert_contains "$out" "⚠"
}
