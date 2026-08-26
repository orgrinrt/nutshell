#!/usr/bin/env bash
# Tests for which repository the QA gate reads.
#
# The gate reported PASSED WITH WARNINGS in two consumers and none of it was
# about them. `_find_repo_root` walked up from this file, which lands on
# whichever nutshell is running the check, so the thresholds were the
# consumer's and the files they were applied to were nutshell's. Nothing in
# either consumer's source had ever been read, and `paths.exclude` naming the
# vendored directory could not help, because the walk began inside it.
#
# It is not only a vendoring problem: a consumer resolving nutshell out of the
# store gets the same answer, because a store checkout carries a `.git` too.

use test

. "${BASH_SOURCE[0]%/*}/../lib/check-runner.sh"

_CR_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-checkroot.XXXXXX")"
trap '[[ -n "${_CR_TMP:-}" ]] && rm -rf "$_CR_TMP"' EXIT

# A consumer, and a nutshell sitting inside it the way a vendored or
# store-resolved one does.
_cr_consumer() {
    local d="$_CR_TMP/$1"
    mkdir -p "$d/lib/nutshell/lib" "$d/libs"
    printf '[meta]\nname = "%s"\n' "$1" > "$d/nut.toml"
    mkdir -p "$d/.git"
    printf '[meta]\nname = "nutshell"\n' > "$d/lib/nutshell/nut.toml"
    mkdir -p "$d/lib/nutshell/.git"
    printf '%s' "$d"
}

#[test]
it_reads_the_repository_the_check_was_run_from() {
    local d; d="$(_cr_consumer one)"
    local got; got="$(cd "$d" && _CHECK_RUNNER_DIR="$d/lib/nutshell/lib" NUTSHELL_CONFIG="" _find_repo_root)"
    assert_eq "$got" "$(cd "$d" && pwd)"
}

#[test]
it_does_not_read_the_nutshell_that_is_running_the_check() {
    # The defect, stated as its own case. The runner sits inside the consumer,
    # in a directory that is itself a repository, which is exactly what the
    # old walk stopped at.
    local d; d="$(_cr_consumer two)"
    local got; got="$(cd "$d" && _CHECK_RUNNER_DIR="$d/lib/nutshell/lib" NUTSHELL_CONFIG="" _find_repo_root)"
    assert_ne "$got" "$(cd "$d/lib/nutshell" && pwd)"
}

#[test]
it_reads_the_repository_from_a_directory_inside_it() {
    # `./check` is run from the root, but a person in a subdirectory reaching
    # for an installed one means the same project.
    local d; d="$(_cr_consumer three)"
    mkdir -p "$d/libs/tui"
    local got; got="$(cd "$d/libs/tui" && _CHECK_RUNNER_DIR="$d/lib/nutshell/lib" NUTSHELL_CONFIG="" _find_repo_root)"
    assert_eq "$got" "$(cd "$d" && pwd)"
}

#[test]
it_takes_the_directory_of_a_config_that_was_named() {
    # A config file states which repository it is the config for, and that
    # outranks where the command happened to be typed.
    local d e
    d="$(_cr_consumer four)"; e="$(_cr_consumer five)"
    local got; got="$(cd "$e" && NUTSHELL_CONFIG="$d/nut.toml" _find_repo_root)"
    assert_eq "$got" "$(cd "$d" && pwd)"
}

#[test]
it_reads_nutshell_itself_when_it_is_checking_itself() {
    # The case that always worked and has to keep working: nutshell's own
    # `./check`, run at nutshell's own root.
    local root; root="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
    local got; got="$(cd "$root" && NUTSHELL_CONFIG="" _find_repo_root)"
    assert_eq "$got" "$root"
}

#[test]
it_falls_back_to_the_interpreter_when_nothing_above_says_repository() {
    # Run from somewhere that is not a project at all. There is nothing to
    # check but the interpreter, and saying so beats reporting on a directory
    # nobody asked about.
    local bare="$_CR_TMP/bare"; mkdir -p "$bare"
    local fake="$_CR_TMP/fakenut/lib"; mkdir -p "$fake"
    mkdir -p "$_CR_TMP/fakenut/.git"
    local got; got="$(cd "$bare" && _CHECK_RUNNER_DIR="$fake" NUTSHELL_CONFIG="" _find_repo_root)"
    assert_eq "$got" "$(cd "$_CR_TMP/fakenut" && pwd)"
}

#[test]
it_refuses_to_walk_from_a_directory_that_is_not_there() {
    assert_fails _walk_to_marker "$_CR_TMP/no-such-directory"
    assert_fails _walk_to_marker ""
}
