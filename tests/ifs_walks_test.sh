#!/usr/bin/env bash
# Tests that no library walk reads the caller's IFS.
#
# A caller may hold IFS at anything, `local IFS=:` around a PATH walk being the
# ordinary case, and a library function that splits a list of its own on
# whitespace, or joins `$*` into a message, has to do it as written whatever
# the caller holds. `deps` has its own file, `deps_ifs_test.sh`; this one is
# the rest of `lib/`. Each case runs in a child with IFS set after the
# modules are loaded, under a colon, a comma and none at all, and prints a
# literal written here.

use test

_IW_IFS_VALUES=(":" "," "")

# _iw_nut <ifs> <modules> <body> -> stdout and stderr of the body, in nutshell
_iw_nut() {
    env -i HOME="$HOME" PATH="$PATH" bash -c '
        . "$1/init" || exit 1
        use $3
        IFS="$2"
        eval "$4"
    ' _ "$NUTSHELL_ROOT" "$1" "$2" "$3" 2>&1
}

# _iw_each <modules> <expected> <body> -> the body prints the expected under every IFS
_iw_each() {
    local mods="$1" want="$2" body="$3" v got
    for v in "${_IW_IFS_VALUES[@]}"; do
        got="$(_iw_nut "$v" "$mods" "$body")"
        assert_eq "$got" "$want" "IFS=[$v]" || return 1
    done
}

# A POSIX shell that is one, or nothing: the floors run under it.
_iw_posix_shell() {
    command -v dash >/dev/null 2>&1 && { printf dash; return 0; }
    return 1
}

# _iw_floor <file> <body> -> the POSIX floor file driven under a POSIX shell
# with the IFS of the case; one line per IFS value tried
_iw_floor() {
    local sh="$1" file="$2" body="$3" v
    for v in "${_IW_IFS_VALUES[@]}"; do
        "$sh" -c '. "$1"; IFS="$2"; eval "$3"; printf "|%s" "${IFS-unset}"' _ "$file" "$v" "$body" 2>&1
        printf '\n'
    done
}

#[test]
it_walks_the_posix_map_whatever_ifs_the_caller_holds() {
    local sh; sh="$(_iw_posix_shell)" || { skip "no dash on this machine"; return 0; }
    local out want=$'3 a\nb\nc 2 0'
    local v got
    for v in "${_IW_IFS_VALUES[@]}"; do
        got="$("$sh" -c '
            nut_once() { return 0; }
            . "$1"; map_new m; map_set m a 1; map_set m b 2; map_set m c 3
            IFS="$2"
            printf "%s " "$(map_len m)"
            printf "%s" "$(map_keys m | tr "\n" " " | sed "s/ \$//; s/ /\\n/g")"
            map_del m b
            printf " %s" "$(map_len m)"
            map_clear m
            printf " %s" "$(map_len m)"' _ "$NUTSHELL_ROOT/lib/map.sh" "$v" 2>&1)"
        assert_eq "$got" "$want" "IFS=[$v]" || return 1
    done
}

#[test]
it_puts_the_callers_ifs_back_after_a_posix_map_walk() {
    local sh; sh="$(_iw_posix_shell)" || { skip "no dash on this machine"; return 0; }
    local v got
    for v in "${_IW_IFS_VALUES[@]}"; do
        got="$("$sh" -c '
            nut_once() { return 0; }
            . "$1"; map_new m; map_set m a 1
            IFS="$2"
            map_len m >/dev/null; map_keys m >/dev/null; map_del m a; map_clear m
            printf "[%s]" "$IFS"' _ "$NUTSHELL_ROOT/lib/map.sh" "$v" 2>&1)"
        assert_eq "$got" "[$v]" "IFS=[$v]" || return 1
    done
}

#[test]
it_puts_back_an_unset_ifs_after_a_posix_map_walk() {
    local sh; sh="$(_iw_posix_shell)" || { skip "no dash on this machine"; return 0; }
    local got
    got="$("$sh" -c '
        nut_once() { return 0; }
        . "$1"; map_new m; map_set m a 1
        unset IFS
        map_len m >/dev/null
        printf "%s" "${IFS-unset}"' _ "$NUTSHELL_ROOT/lib/map.sh" 2>&1)"
    assert_eq "$got" "unset"
}

#[test]
it_measures_a_distance_in_the_posix_floor_whatever_ifs_is_held() {
    local sh; sh="$(_iw_posix_shell)" || { skip "no dash on this machine"; return 0; }
    local v got
    for v in "${_IW_IFS_VALUES[@]}"; do
        got="$("$sh" -c '
            nut_once() { return 0; }
            . "$1"
            IFS="$2"
            printf "%s " "$(str_distance kitten sitting)"
            printf "%s" "$(str_distance build buidl)"
            printf "[%s]" "$IFS"' _ "$NUTSHELL_ROOT/lib/string.posix.sh" "$v" 2>&1)"
        assert_eq "$got" "3 2[$v]" "IFS=[$v]" || return 1
    done
}

#[test]
it_builds_the_jq_flags_whatever_ifs_the_caller_holds() {
    if ! deps_has jq && ! deps_has gojq && ! deps_has jaq; then
        skip "no jq, gojq or jaq on this machine"; return 0
    fi
    _iw_each json "x" "json_query -r '.a' '{\"a\":\"x\"}'"
}

#[test]
it_runs_a_json_query_with_several_flags_whatever_ifs_is_held() {
    if ! deps_has jq && ! deps_has gojq && ! deps_has jaq; then
        skip "no jq, gojq or jaq on this machine"; return 0
    fi
    # `-c -r -n -e` are four flags the call builds into one string and splits.
    _iw_each json "7" "json_query -r -n -e '3 + 4'"
}

#[test]
it_reads_the_module_graph_whatever_ifs_the_caller_holds() {
    local fx="$NUTSHELL_ROOT/tests/fixtures/lib"
    _iw_each "modgraph" "alpha beta cyclic_a cyclic_b idle subst " "
        MODGRAPH_NOCACHE=1 modgraph_build '$fx'
        modgraph_modules | sort | tr '\\n' ' '"
}

#[test]
it_finds_a_module_cycle_whatever_ifs_the_caller_holds() {
    local fx="$NUTSHELL_ROOT/tests/fixtures/lib" v got
    for v in "${_IW_IFS_VALUES[@]}"; do
        got="$(_iw_nut "$v" modgraph "
            MODGRAPH_NOCACHE=1 modgraph_build '$fx'
            modgraph_cycle")"
        assert_contains "$got" "cyclic_a" "IFS=[$v]" || return 1
        assert_contains "$got" "cyclic_b" "IFS=[$v]" || return 1
        assert_not_contains "$got" "not found" "IFS=[$v]" || return 1
    done
}

#[test]
it_audits_the_module_graph_whatever_ifs_the_caller_holds() {
    local fx="$NUTSHELL_ROOT/tests/fixtures/lib" v got
    for v in "${_IW_IFS_VALUES[@]}"; do
        got="$(_iw_nut "$v" modgraph "
            MODGRAPH_NOCACHE=1 modgraph_build '$fx'
            modgraph_audit")"
        assert_contains "$got" "undeclared" "IFS=[$v]" || return 1
    done
}

#[test]
it_reads_a_toml_comment_whatever_ifs_the_caller_holds() {
    local t; t="$(mktemp -d)"
    printf '# above\na = 1  # after\n' > "$t/c.toml"
    _iw_each "toml toml::comment" $'above\nafter' "toml_comment '$t/c.toml' a"
    local rc=$?
    rm -rf "$t"
    return "$rc"
}

#[test]
it_joins_a_log_message_with_spaces_whatever_ifs_is_held() {
    # `"$*"` joins on the first character of IFS.
    _iw_each log "a b c" "LOG_COLOR=never; log_info a b c 2>&1 | sed 's/^.*\\] //'"
}

#[test]
it_joins_the_words_of_a_failed_assertion_with_spaces() {
    _iw_each test "a b c" '_test_words a b c'
}

#[test]
it_leaves_the_command_an_assertion_runs_its_ifs() {
    # The join is scoped to its own helper, not the assertions: they run the
    # command, which has to see the IFS the test body held.
    _iw_each test "[:]" '
        _show() { printf "[%s]" "$IFS"; }
        IFS=:
        assert_ok _show'
}
