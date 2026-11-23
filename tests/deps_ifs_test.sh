#!/usr/bin/env bash
# Tests for `deps` under a caller's changed IFS.
#
# A caller may hold IFS at anything: `local IFS=:` around a PATH walk is the
# ordinary case. Every list `deps` keeps is space-separated and split with
# plain word splitting, so each walk has to read it as the library wrote it,
# whatever the caller's IFS is. Each case runs in a child process with two
# reset hooks registered and the caller's IFS set after the registering.

use deps test

# The IFS values the matrix runs: a colon, a comma, and none at all.
_DI_IFS_VALUES=(":" "," "")

# _di_child <ifs> <body> -> stdout and stderr of the body, run with the IFS
_di_child() {
    env -i HOME="$HOME" PATH="$PATH" bash -c '
        . "$1/init" || exit 1
        use deps
        _h1() { printf "h1;"; }
        _h2() { printf "h2;"; }
        deps_on_reset _h1
        deps_on_reset _h2
        IFS="$2"
        eval "$3"
    ' _ "$NUTSHELL_ROOT" "$1" "$2" 2>&1
}

# _di_each <expected> <body> -> the body prints the expected under every IFS
_di_each() {
    local want="$1" body="$2" v got
    for v in "${_DI_IFS_VALUES[@]}"; do
        got="$(_di_child "$v" "$body")"
        assert_eq "$got" "$want" || return 1
    done
}

# _di_same <body> -> the body prints what it prints under the default IFS
_di_same() {
    local body="$1" v want got
    want="$(_di_child $' \t\n' "$body")"
    [ -n "$want" ] || { _test_failed "the control printed nothing for [$body]"; return 1; }
    for v in "${_DI_IFS_VALUES[@]}"; do
        got="$(_di_child "$v" "$body")"
        assert_eq "$got" "$want" || return 1
    done
}

#[test]
it_runs_every_reset_hook_on_a_forget_of_all() {
    _di_each 'h1;h2;' 'deps_has sh; deps_forget'
}

#[test]
it_runs_every_reset_hook_on_a_forget_of_one_tool() {
    _di_each 'h1;h2;' 'deps_has sh; deps_forget sh'
}

#[test]
it_runs_every_reset_hook_on_a_hide() {
    _di_each 'h1;h2;' 'deps_has sh; deps_hide sh'
}

#[test]
it_prints_nothing_beside_the_hooks_on_a_forget() {
    # The failure was a "command not found" line, the hooks read as one word.
    _di_each 'h1;h2;' 'deps_has sh; deps_has cat; deps_forget cat; :'
}

#[test]
it_drops_a_forgotten_tool_from_what_it_has_seen() {
    # Held in the lists the walks rewrite: a forgotten tool stays in neither.
    _di_each 'seen=no avail=no;' '
        deps_has sh; deps_has cat; deps_available >/dev/null
        deps_forget sh >/dev/null
        s=no a=no
        case " $_DEPS_SEEN " in *" sh "*) s=yes ;; esac
        case " $_TOOLS_AVAILABLE " in *" sh "*) a=yes ;; esac
        printf "seen=%s avail=%s;" "$s" "$a"'
}

#[test]
it_drops_every_capability_on_a_forget() {
    _di_each 'caps=0;' '
        deps_can grep_pcre >/dev/null 2>&1 || true
        deps_forget >/dev/null
        printf "caps=%s;" "$(printf "%s" "$_TOOL_CAN_NAMES" | wc -w | tr -d " ")"'
}

#[test]
it_leaves_the_callers_variables_alone_on_dropping_capabilities() {
    # `unset _TOOL_CAN_ a b c` was run with the names split apart, which also
    # unset the caller's variables called a, b and c.
    _di_each 'a=1 b=2;' '
        deps_can grep_pcre >/dev/null 2>&1 || true
        a=1 b=2
        deps_hide sh >/dev/null
        printf "a=%s b=%s;" "${a-unset}" "${b-unset}"'
}

#[test]
it_hides_each_tool_of_a_list_and_keeps_the_list_whole() {
    _di_each 'hide=sh cat;' '
        deps_hide sh cat >/dev/null
        printf "hide=%s;" "$NUT_DEPS_HIDE"'
}

#[test]
it_removes_only_the_named_tool_from_the_hide_list_on_a_forget() {
    _di_each 'hide=cat; cat_found=no;' '
        deps_hide sh cat >/dev/null
        deps_forget sh >/dev/null
        printf "hide=%s; " "$NUT_DEPS_HIDE"
        deps_has cat && printf "cat_found=yes;" || printf "cat_found=no;"'
}

#[test]
it_answers_absent_for_hidden_tools_under_any_ifs() {
    _di_each 'sh=no cat=no;' '
        deps_hide sh cat >/dev/null
        s=yes c=yes
        deps_has sh || s=no
        deps_has cat || c=no
        printf "sh=%s cat=%s;" "$s" "$c"'
}

#[test]
it_reads_the_manifest_again_when_the_script_moves_under_any_ifs() {
    # `_deps_sync_config` walks the tools it knows to apply a new manifest's
    # pins: a pin that names a path that is not there refuses the tool.
    local t; t="$(mktemp -d)"
    mkdir "$t/pinned"
    printf '[deps.paths]\nsh = "/nonexistent/sh"\n' > "$t/pinned/nut.toml"
    _di_each 'before=yes after=no;' "
        deps_has sh; deps_has cat
        b=yes a=yes
        deps_has sh || b=no
        cd '$t/pinned' || exit 1
        deps_has sh || a=no
        printf 'before=%s after=%s;' \"\$b\" \"\$a\""
    local rc=$?
    rm -rf "$t"
    return "$rc"
}

#[test]
it_answers_every_public_question_alike_under_any_ifs() {
    _di_same '
        deps_has_all sh cat && printf "all;"
        deps_has_any nonexistent_tool_xyz sh && printf "any;"
        deps_available | tr " " "\n" | sort | tr "\n" ","
        printf "path=%s;" "$(deps_path sh)"
        printf "variant=%s;" "$(deps_variant sed)"
        deps_is_gnu sed && printf "gnu;"
        deps_is_bsd sed && printf "bsd;"
        deps_can grep_pcre && printf "pcre;"
        printf "cap=%s;" "$(deps_cap grep_pcre)"
        deps_caps | sort | tr "\n" ","
        deps_check sh cat >/dev/null 2>&1; printf "check=%s;" "$?"
        deps_require sh >/dev/null 2>&1; printf "require=%s;" "$?"
        deps_require_all sh cat >/dev/null 2>&1; printf "requireall=%s;" "$?"
        deps_run sh -c "printf run;"'
}

#[test]
it_reports_a_missing_tool_the_same_under_any_ifs() {
    _di_same '
        deps_has_all sh nonexistent_tool_xyz || printf "all-no;"
        deps_check sh nonexistent_tool_xyz 2>&1; printf "check=%s;" "$?"
        (deps_require_all sh nonexistent_tool_xyz) 2>&1; printf "requireall=%s;" "$?"
        deps_hide cat
        deps_run cat /dev/null 2>&1; printf "run=%s;" "$?"'
}
