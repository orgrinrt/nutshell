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
