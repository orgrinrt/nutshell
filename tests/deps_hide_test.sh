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

use deps json http toml text fs test

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

# A module picks its tool once and keeps the pick. A hide, or a forget, has to
# reach every such pick, or the module goes on answering with a tool `deps`
# says is not there. Each test below picks in this shell first, then hides.

# _dh_has_any <tool...> -> 0 when the machine has at least one of them
_dh_has_any() { local t; for t in "$@"; do deps_has "$t" && return 0; done; return 1; }

#[test]
it_moves_json_to_python_when_jq_is_hidden_after_it_picked_jq() {
    deps_has jq || { skip "jq is not on this machine"; return 0; }
    _dh_has_any python3 python || { skip "python is not on this machine"; return 0; }
    json_get '{"a":1.5}' a > /dev/null
    json_impl > /dev/null
    assert_eq "$(json_impl)" "jq" "the pick before the hide"
    deps_hide jq
    assert_eq "$(json_impl)" "python"
    assert_eq "$(json_get '{"a":1.5}' a)" "1.5"
    local out rc=0
    out="$(json_set '{"a":1}' a 2 2>&1)" || rc=$?
    assert_eq "$rc" "0" "json_set after the hide: $out"
    assert_eq "$out" '{"a":2}'
}

#[test]
it_moves_json_to_python_when_jq_is_forgotten_from_the_environment_list() {
    deps_has jq || { skip "jq is not on this machine"; return 0; }
    _dh_has_any python3 python || { skip "python is not on this machine"; return 0; }
    json_impl > /dev/null
    deps_hide jq
    assert_eq "$(json_impl)" "python"
    deps_forget
    json_impl > /dev/null
    assert_eq "$(json_impl)" "jq" "a forget brings the tool back to the pick"
}

#[test]
it_refuses_json_set_with_status_2_when_every_tool_is_hidden_after_a_pick() {
    deps_has jq || { skip "jq is not on this machine"; return 0; }
    json_impl > /dev/null
    deps_hide jq python3 python perl
    local rc=0
    json_set '{"a":1}' a 2 > /dev/null 2>&1 || rc=$?
    assert_eq "$rc" "2" "the bash floor cannot write"
}

#[test]
it_moves_http_to_wget_when_curl_is_hidden_after_it_picked_curl() {
    deps_has curl && deps_has wget || { skip "curl and wget are not both here"; return 0; }
    assert_eq "$(http_impl)" "curl"
    deps_hide curl
    assert_eq "$(http_impl)" "wget"
    deps_forget
    assert_eq "$(http_impl)" "curl"
}

#[test]
it_moves_text_when_the_tool_it_picked_is_hidden() {
    deps_has grep && deps_has sed || { skip "grep and sed are not both here"; return 0; }
    local f; f="$(mktemp)"; printf 'one\ntwo\n' > "$f"
    text_replace one 1 "$f" > /dev/null 2>&1
    assert_eq "$_TEXT_REPLACE_IMPL" "grep_sed" "the pick before the hide"
    deps_hide grep
    text_replace two 2 "$f" > /dev/null 2>&1
    assert_eq "$_TEXT_REPLACE_IMPL" "sed" "the pick after hiding grep"
    text_grep 2 "$f" > /dev/null 2>&1
    assert_ne "$_TEXT_MATCH_IMPL" "grep"
    deps_hide sed perl awk
    assert_fails text_ready
    rm -f "$f"
}

#[test]
it_moves_fs_when_stat_and_perl_are_hidden_after_it_picked() {
    deps_has stat || { skip "stat is not on this machine"; return 0; }
    local f; f="$(mktemp)"; printf 'abc' > "$f"
    assert_eq "$(fs_size "$f")" "3"
    assert_ok fs_ready
    deps_hide stat perl
    assert_fails fs_ready
    local rc=0
    fs_size "$f" > /dev/null 2>&1 || rc=$?
    assert_ne "$rc" "0" "fs_size with no stat tool"
    rm -f "$f"
}

#[test]
it_moves_toml_to_the_floor_when_its_tool_is_hidden_after_it_picked() {
    _dh_has_any taplo yq || { skip "neither taplo nor yq is here"; return 0; }
    local f; f="$(mktemp)"; printf 'a = 1\n' > "$f"
    toml_get "$f" a > /dev/null
    case "$_TOML_BACKEND" in taplo|yq) ;; *) skip "no toml tool was picked: $_TOML_BACKEND"; rm -f "$f"; return 0 ;; esac
    deps_hide taplo yq
    toml_get "$f" a > /dev/null
    assert_eq "$_TOML_BACKEND" "bash"
    rm -f "$f"
}

#[test]
it_keeps_the_environments_hide_list_across_a_bare_forget() {
    local out
    out="$(env -i HOME="$HOME" PATH="$PATH" NUT_DEPS_HIDE=cat bash -c '
        . "$1/init" || exit 1
        use deps
        deps_hide sh
        deps_forget
        deps_has cat && printf "cat-found "
        deps_has sh && printf "sh-found "
        printf "list=%s" "${NUT_DEPS_HIDE:-}"
    ' _ "$NUTSHELL_ROOT" 2>&1)"
    assert_eq "$out" "sh-found list=cat"
}

#[test]
it_clears_every_hide_on_a_bare_forget_where_the_environment_named_none() {
    deps_hide "$_DH_TOOL"
    deps_forget
    assert_eq "${NUT_DEPS_HIDE:-}" ""
    assert_ok deps_has "$_DH_TOOL"
}
