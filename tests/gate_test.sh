#!/usr/bin/env bash
# Tests for gating a module on the shell or on a tool.
#
# A gate is a comment line in attribute shape, above the declaration it applies
# to, the way `#[cfg(...)]` sits above a `mod` in Rust:
#
#     #[shell(bash4)]
#     string  lib/string.sh
#     string  lib/string.posix.sh
#
# `#` already means comment in this format, so a reader that knows nothing
# about gates skips them and the file stays what it was. Same trick `attr` uses
# for `#[pub]` in a shell file.
#
# The decision is taken **before the file is sourced**, which is the whole
# reason it lives here rather than inside a module. A file using a construct
# the running shell cannot parse fails at parse time, so no `if` inside it can
# guard it: the guard has to sit above the sourcing.
#
# The row with no gate above it is the floor and always holds. Order in the
# file is the order tried, so a floor above a better row makes that row
# unreachable, and there is a test for that rather than a comment asking
# somebody to be careful.

use test

_G_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-gate.XXXXXX")"
trap '[[ -n "${_G_TMP:-}" ]] && rm -rf "$_G_TMP"' EXIT

# A library root with a manifest and the files it names.
_g_lib() {
    local d; d="$(mktemp -d "${_G_TMP}/lib.XXXXXX")"
    printf '%s' "$1" > "$d/lib.nut"
    local f
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        mkdir -p "$d/${f%/*}" 2>/dev/null
        printf 'MARK=%s\n' "${f##*/}" > "$d/$f"
    done < <(awk '!/^#/ && NF>=2 {print $2}' "$d/lib.nut" | sort -u)
    printf '%s' "$d"
}

_g_pick() {
    local got; got="$(_lib_nut_lookup "$1" "$2" 2>/dev/null)" || return 1
    printf '%s' "${got##*/}"
}

HERE="has(bin(sh))"
GONE="has(bin(no-such-command-anywhere-3f9a))"

# --- the gate itself ---------------------------------------------------------

#[test]
it_holds_for_a_command_that_is_here() {
    assert_ok _nut_gate "$HERE"
}

#[test]
it_does_not_hold_for_a_command_that_is_not() {
    # The control for the one above. A gate that always held would pass every
    # test in this file and select the first row on every machine.
    assert_fails _nut_gate "$GONE"
}

#[test]
it_holds_for_the_shell_that_is_running_this() {
    assert_ok _nut_gate "shell(bash)"
    assert_ok _nut_gate "shell(bash4)"
}

#[test]
it_reads_the_bash_floor_the_same_way_init_does() {
    # `shell(bash4)` and `init`'s own guard answer one question, and two
    # answers to it is how a floor drifts. `10.0.0` is the row worth having:
    # `1.*` is a prefix of `1.` rather than of `1`.
    local v want got
    for v in '' 1.14.7 2.05b '3.2.57(1)-release' 4.0 '4.0.0-beta' 5.3 10.0.0; do
        case "$v" in ''|1.*|2.*|3.*) want=no ;; *) want=yes ;; esac
        got=no
        BASH_VERSION="$v" _nut_gate "shell(bash4)" && got=yes
        assert_eq "$got" "$want" "BASH_VERSION=[$v]"
    done
}

#[test]
it_reads_an_environment_variable() {
    export _NUT_GATE_PROBE=1
    assert_ok _nut_gate "has(env(_NUT_GATE_PROBE))"
    unset _NUT_GATE_PROBE
    assert_fails _nut_gate "has(env(_NUT_GATE_PROBE))"
    _NUT_GATE_EMPTY="" assert_fails _nut_gate "has(env(_NUT_GATE_EMPTY))"
    assert_fails _nut_gate "has(env())"
}

#[test]
it_refuses_an_attribute_it_does_not_know() {
    # A typo must not read as true. Read as true it promotes a variant onto
    # every machine, which is the opposite of what a gate is for, and nothing
    # about the tree would look wrong.
    assert_fails _nut_gate "hav(bin(grep))"
    assert_fails _nut_gate "shell(zsh)"
    assert_fails _nut_gate "wat"
    assert_fails _nut_gate "has(lib(m))"
}

#[test]
it_holds_for_nothing_at_all() {
    # No gate is the floor, which is what a row with nothing above it gets.
    assert_ok _nut_gate ""
}

#[test]
it_does_not_run_what_is_written_in_the_file() {
    # The text comes out of a file on disk and is never evaluated as shell.
    # `eval` here would be arbitrary execution in the one place that runs
    # before anything else in the library.
    local witness="$_G_TMP/witness"
    rm -f "$witness"
    _nut_gate "has(env(X; touch $witness))" 2>/dev/null || true
    _nut_gate "has(bin(sh; touch $witness))" 2>/dev/null || true
    _nut_gate "shell(bash); touch $witness" 2>/dev/null || true
    assert_fails test -e "$witness"
}

# --- what is remembered ------------------------------------------------------

#[test]
it_gives_the_same_answer_for_a_binary_the_second_time() {
    assert_ok    _nut_gate "$HERE"
    assert_ok    _nut_gate "$HERE"
    assert_fails _nut_gate "$GONE"
    assert_fails _nut_gate "$GONE"
}

#[test]
it_does_not_remember_an_answer_that_can_change() {
    # `env` is a caller's variable and `shell` is read from one, so neither is
    # cached. Caching them made a gate answer once for every value it was ever
    # asked about, which is the cache being wrong rather than the caller being
    # awkward.
    local before after
    BASH_VERSION='5.0' _nut_gate "shell(bash4)" && before=yes || before=no
    BASH_VERSION='3.2' _nut_gate "shell(bash4)" && after=yes  || after=no
    assert_eq "$before" "yes"
    assert_eq "$after"  "no"
}

#[test]
it_does_not_let_a_remembered_binary_answer_for_a_different_one() {
    # Keyed by the whole attribute. Keying by anything coarser makes one answer
    # stand for several questions.
    assert_ok    _nut_gate "$HERE"
    assert_fails _nut_gate "$GONE"
    assert_ok    _nut_gate "$HERE"
}

# --- choosing a file ---------------------------------------------------------

#[test]
it_takes_the_first_row_whose_gate_holds() {
    local d; d="$(_g_lib "#[${GONE}]
thing  a.sh
#[${HERE}]
thing  b.sh
thing  c.sh")"
    assert_eq "$(_g_pick "$d" thing)" "b.sh"
}

#[test]
it_falls_to_the_row_with_no_gate() {
    local d; d="$(_g_lib "#[${GONE}]
thing  a.sh
thing  c.sh")"
    assert_eq "$(_g_pick "$d" thing)" "c.sh"
}

#[test]
it_finds_nothing_when_no_gate_holds_and_there_is_no_floor() {
    # A library with only gated rows can fail to resolve on a machine matching
    # none of them. That is the library's defect and the resolver says so
    # rather than picking one anyway.
    local d; d="$(_g_lib "#[${GONE}]
thing  a.sh")"
    assert_fails _g_pick "$d" thing
}

#[test]
it_reads_the_order_in_the_file_as_the_order_to_try() {
    # The same two rows the other way round. A floor above a better row makes
    # that row unreachable, and this is what says so.
    local d; d="$(_g_lib "thing  c.sh
#[${HERE}]
thing  b.sh")"
    assert_eq "$(_g_pick "$d" thing)" "c.sh"
}

#[test]
it_wants_every_gate_in_a_run_to_hold() {
    # They accumulate, the way several `#[cfg]` lines do above one `mod`.
    local d; d="$(_g_lib "#[${HERE}]
#[${GONE}]
thing  a.sh
thing  c.sh")"
    assert_eq "$(_g_pick "$d" thing)" "c.sh"

    d="$(_g_lib "#[${HERE}]
#[shell(bash)]
thing  a.sh
thing  c.sh")"
    assert_eq "$(_g_pick "$d" thing)" "a.sh"

    # The false one first. Both orders, because with the false gate always
    # last a run that kept only the last gate answers the same as one that
    # keeps them all, and this test passed while that was true.
    d="$(_g_lib "#[${GONE}]
#[${HERE}]
thing  a.sh
thing  c.sh")"
    assert_eq "$(_g_pick "$d" thing)" "c.sh"
}

#[test]
it_does_not_carry_a_gate_past_the_row_it_applies_to() {
    # A gate attaches to the next declaration and stops there. Carried on, one
    # false gate near the top would hide every row under it.
    local d; d="$(_g_lib "#[${GONE}]
thing  a.sh
other  b.sh")"
    assert_eq "$(_g_pick "$d" other)" "b.sh"
}

#[test]
it_still_resolves_a_module_with_no_gate_anywhere() {
    # The control for the whole feature. Every existing manifest is rows with
    # no gate at all, and a change that broke those would be caught elsewhere
    # in the suite but not by anything in this file.
    local d; d="$(_g_lib 'one  one.sh
two  two.sh')"
    assert_eq "$(_g_pick "$d" one)" "one.sh"
    assert_eq "$(_g_pick "$d" two)" "two.sh"
}

#[test]
it_still_refuses_an_internal_module_from_outside() {
    # The gate lines must not have opened the visibility door. Reading a
    # leading `#[` and continuing is exactly the shape that could.
    local d; d="$(_g_lib "#[${HERE}]
thing  a.sh  internal")"
    assert_fails _lib_nut_lookup "$d" thing public
    assert_eq "$(_g_pick "$d" thing)" "a.sh"
}

#[test]
it_still_treats_an_ordinary_comment_as_a_comment() {
    local d; d="$(_g_lib "# just prose
thing  a.sh")"
    assert_eq "$(_g_pick "$d" thing)" "a.sh"
}
