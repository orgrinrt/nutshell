#!/usr/bin/env bash
# Tests for telling `deps` a tool is not there, and for what the first tool
# question of a process reads.
#
# `deps_hide` makes `deps` answer absent for a tool the machine has, so a
# script, or a test, can run the path a machine without it takes;
# `NUT_DEPS_HIDE` carries the same to a child process. The first question of a
# process reads the manifest for a `[deps.paths]` pin only where the manifest
# could hold one for that tool, so a hook that asks for jq does not load the
# toml reader to learn there is no pin.

use deps test

# A tool every machine this runs on has, found on PATH and pinned nowhere.
_DH_TOOL=sh

#[test]
it_answers_absent_for_a_hidden_tool() {
    assert_ok deps_has "$_DH_TOOL"
    deps_hide "$_DH_TOOL"
    assert_fails deps_has "$_DH_TOOL"
    assert_fails deps_path "$_DH_TOOL"
    assert_fails deps_has_any "$_DH_TOOL"
    assert_eq "$(deps_path "$_DH_TOOL")" ""
    assert_ok deps_has cat "another tool is still there"
}

#[test]
it_refuses_to_run_a_hidden_tool() {
    deps_hide "$_DH_TOOL"
    local out rc
    out="$(deps_run "$_DH_TOOL" -c 'echo ran' 2>&1)"; rc=$?
    assert_eq "$rc" "1"
    assert_not_contains "$out" "ran"
    assert_contains "$out" "$_DH_TOOL"
}

#[test]
it_hides_a_tool_already_found() {
    # A tool resolved before the hide is forgotten by it, so the path that was
    # kept is not what answers next.
    assert_ok deps_has "$_DH_TOOL"
    deps_hide "$_DH_TOOL"
    assert_eq "$(eval "printf '%s' \"\${_TOOL_PATH_${_DH_TOOL}:-}\"")" ""
}

#[test]
it_finds_a_hidden_tool_again_after_deps_forget() {
    deps_hide "$_DH_TOOL" cat
    deps_forget
    assert_ok deps_has "$_DH_TOOL"
    assert_ok deps_has cat
}

#[test]
it_finds_only_the_tool_deps_forget_names_again() {
    deps_hide "$_DH_TOOL" cat
    deps_forget cat
    assert_fails deps_has "$_DH_TOOL"
    assert_ok deps_has cat
}

#[test]
it_hides_what_nut_deps_hide_names_in_a_child() {
    local out
    out="$(env -i HOME="$HOME" PATH="$PATH" NUT_DEPS_HIDE="$_DH_TOOL cat" bash -c '
        . "$1/init" || exit 1
        use deps
        deps_has "$2" && printf "%s " "$2"
        deps_has cat && printf "cat "
        deps_has env && printf "env "
        printf done
    ' _ "$NUTSHELL_ROOT" "$_DH_TOOL" 2>&1)"
    assert_eq "$out" "env done"
}

#[test]
it_hands_a_hide_to_a_child_process() {
    deps_hide "$_DH_TOOL"
    local out
    out="$(bash -c '. "$1/init" || exit 1; use deps; deps_has "$2" || printf hidden' _ "$NUTSHELL_ROOT" "$_DH_TOOL" 2>&1)"
    assert_eq "$out" "hidden"
}

#[test]
it_reads_no_manifest_for_a_tool_the_manifest_cannot_name() {
    # A manifest that never spells the tool cannot pin it, so the toml reader
    # is not loaded to find out; the tool is still found on PATH.
    local t; t="$(mktemp -d)"
    printf '[package]\nname = "x"\n\n[deps.paths]\nsed = "/bin/sed"\n' > "$t/nut.toml"
    local out
    out="$(cd "$t" && env -i HOME="$HOME" PATH="$PATH" bash -c '
        . "$1/init" || exit 1
        use deps
        deps_has env && printf "found "
        nutshell_loaded toml && printf "toml "
        printf done
    ' _ "$NUTSHELL_ROOT" 2>&1)"
    rm -rf "$t"
    assert_eq "$out" "found done"
}

#[test]
it_reads_a_pin_spelled_with_an_escape() {
    # The control for the one above: a key written with a `\u` escape does not
    # spell the tool's name in the text, and is still a pin.
    local t; t="$(mktemp -d)"
    printf '[deps.paths]\n"\\u0073ed" = "/nonexistent/sed"\n' > "$t/nut.toml"
    local out
    out="$(cd "$t" && env -i HOME="$HOME" PATH="$PATH" bash -c '
        . "$1/init" || exit 1
        use deps
        deps_has sed && printf "found "
        printf done
    ' _ "$NUTSHELL_ROOT" 2>/dev/null)"
    rm -rf "$t"
    assert_eq "$out" "done"
}

#[test]
it_loads_neither_os_nor_the_probes_for_a_presence_question() {
    local out
    out="$(env -i HOME="$HOME" PATH="$PATH" bash -c '
        . "$1/init" || exit 1
        use deps
        deps_has env >/dev/null
        nutshell_loaded os && printf "os "
        declare -F _deps_detect_capabilities >/dev/null && printf "probe "
        declare -F _deps_detect_sed_variant >/dev/null && printf "variants "
        printf done
    ' _ "$NUTSHELL_ROOT" 2>&1)"
    assert_eq "$out" "done"
}
