#!/usr/bin/env bash
# Tests for the generated module map.
#
# `resolver` is `lib.nut` written as a `case`, and the whole argument for it
# is that the two say the same thing. So the test that matters is not that the
# resolver answers, it is that it answers what walking the manifest answers,
# for every module in it.

use test

_R_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
_R_GEN="${_R_ROOT}/bin/nut-gen-resolver"
_R_OUT="${_R_ROOT}/resolver"

# Every module the manifest names, including the internal ones, since their
# refusal is part of what the walk answers.
_r_modules() {
    awk '!/^#/ && NF>=2 {print $1}' "${_R_ROOT}/lib.nut" | sort -u
}

#[test]
# The generated map agrees with the walk about every module.
#
# This is the whole claim. `_lib_nut_lookup` reads `lib.nut` on every lookup and
# `_nut_resolve` reads nothing, so if they ever disagree the generated one is
# wrong and silently: a module resolves to the wrong file, or to none, and the
# failure surfaces as a missing function somewhere else entirely.
it_answers_what_walking_the_manifest_answers() {
    . "$_R_OUT"
    local m walk gen bad="" n=0
    for m in $(_r_modules); do
        n=$(( n + 1 ))
        walk="$(_lib_nut_lookup "$_R_ROOT" "$m" 2>/dev/null)" || walk="REFUSED"
        gen="$(_nut_resolve "$m" "$_R_ROOT" 2>/dev/null)" || gen="REFUSED"
        [ "$walk" = "$gen" ] || bad="${bad} [${m}: walk=${walk} gen=${gen}]"
    done
    assert_eq "$bad" "" "the map and the manifest disagree"
    # The control. A loop over nothing agrees with everything, and this file
    # has forty-odd rows in it.
    assert_ok test "$n" -gt 30
}

#[test]
# And about an internal module reached publicly, which is a refusal rather than
# a path and is the one answer easiest to lose in a rewrite.
it_refuses_an_internal_module_the_same_way() {
    . "$_R_OUT"
    local m walk gen bad="" n=0
    for m in $(awk '$3=="internal" {print $1}' "${_R_ROOT}/lib.nut"); do
        n=$(( n + 1 ))
        walk="$(_lib_nut_lookup "$_R_ROOT" "$m" public 2>/dev/null)" || walk="REFUSED"
        gen="$(_nut_resolve "$m" "$_R_ROOT" public 2>/dev/null)" || gen="REFUSED"
        [ "$walk" = "$gen" ] || bad="${bad} [${m}: walk=${walk} gen=${gen}]"
    done
    assert_eq "$bad" ""
    assert_ok test "$n" -gt 0
}

#[test]
# It is POSIX, which `init` is not and cannot be.
#
# The entry point is the one file a POSIX shell could never read, so every
# floor number measured so far has been about lowered artifacts with that door
# still shut. A generated `case` has no associative array in it.
it_reads_and_runs_under_a_posix_shell() {
    local sh probe
    probe="$(mktemp)"; printf 'a=(1 2)\n' > "$probe"
    for sh in dash ash yash posh sh; do
        command -v "$sh" >/dev/null 2>&1 || continue
        "$sh" -n "$probe" >/dev/null 2>&1 && continue
        break
    done
    rm -f "$probe"
    assert_ne "$sh" ""
    assert_ok "$sh" -n "$_R_OUT"

    # And it answers there, which parsing does not establish.
    local got
    got="$("$sh" -c '. "$1"
        _nut_gate() { return 0; }
        _nut_resolve os "$2"' _ "$_R_OUT" /x 2>&1)"
    assert_eq "$got" "/x/lib/os.sh"
}

#[test]
# The generator is deterministic, or the currency check is noise.
#
# A check that regenerates and diffs is only a check if the generator produces
# the same bytes from the same manifest. If it did not, the check would fail at
# random and get switched off, which is worse than not having it.
it_generates_the_same_bytes_twice() {
    local a b
    a="$(mktemp)"; b="$(mktemp)"
    "$_R_GEN" "$_R_ROOT" > "$a" 2>/dev/null
    "$_R_GEN" "$_R_ROOT" > "$b" 2>/dev/null
    assert_ok cmp -s "$a" "$b"
    # And what is committed is what it produces, which is the check's own claim
    # asserted here too so a test failure names it rather than a check run.
    assert_ok cmp -s "$a" "$_R_OUT"
    rm -f "$a" "$b"
}

#[test]
# It refuses a manifest still using the retired `when=` column, rather than
# emitting a map that quietly drops the gate.
it_refuses_a_manifest_with_the_old_gate_column() {
    local d; d="$(mktemp -d)"
    printf 'foo   lib/foo.sh   when=bash4\n' > "$d/lib.nut"
    assert_fails "$_R_GEN" "$d"
    rm -rf "$d"
}
