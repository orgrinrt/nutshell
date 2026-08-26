#!/usr/bin/env bash
# Tests for finding the interpreter.
#
# A copy of nutshell inside a project is a second version that drifts from the
# installed one in silence. It happened twice in one day: a tool pinned at its
# dependency's first commit resolved every module that existed then and none
# added since, and the error named a missing module rather than a stale copy.
#
# So an installed one wins, and a version older than the tool needs is a
# refusal at startup rather than a missing function halfway through a run.

use test

. "${BASH_SOURCE[0]%/*}/../find-nutshell"

# A directory holding something that looks like an interpreter.
_fake_nutshell() {
    local d="$1" version="${2:-9.9.9}"
    mkdir -p "$d/bin"
    printf 'export NUTSHELL_VERSION="%s"\n' "$version" > "$d/init"
    printf '#!/usr/bin/env bash\n' > "$d/bin/nutshell"
    chmod +x "$d/bin/nutshell"
}

_reset() { NUTSHELL_INIT=""; NUTSHELL_FROM=""; unset NUTSHELL_HOME; }

#[test]
it_prefers_what_the_caller_named() {
    _reset
    local d; d="$(mktemp -d)"; _fake_nutshell "$d/named"
    local root; root="$(mktemp -d)"; _fake_nutshell "$root/lib/nutshell"
    NUTSHELL_HOME="$d/named" nutshell_find "$root"
    local from="$NUTSHELL_FROM" init="$NUTSHELL_INIT"
    rm -rf "$d" "$root"; _reset
    assert_eq "$from" "NUTSHELL_HOME"
    assert_contains "$init" "named"
}

#[test]
it_refuses_a_named_home_with_no_interpreter_in_it() {
    # Silently falling through to another one would make the override a
    # suggestion, and an override that is a suggestion is worse than none.
    _reset
    local d; d="$(mktemp -d)"
    local root; root="$(mktemp -d)"; _fake_nutshell "$root/lib/nutshell"
    local rc=0
    NUTSHELL_HOME="$d/nothing" nutshell_find "$root" 2>/dev/null || rc=$?
    rm -rf "$d" "$root"; _reset
    assert_ne "$rc" "0"
}

#[test]
it_prefers_an_installed_one_over_a_vendored_one() {
    # The whole point. A per-project copy is the thing that goes stale.
    _reset
    local d; d="$(mktemp -d)"; _fake_nutshell "$d/installed"
    local root; root="$(mktemp -d)"; _fake_nutshell "$root/lib/nutshell"
    PATH="$d/installed/bin:$PATH" nutshell_find "$root"
    local from="$NUTSHELL_FROM" init="$NUTSHELL_INIT"
    rm -rf "$d" "$root"; _reset
    assert_eq "$from" "installed"
    assert_contains "$init" "installed"
}

#[test]
it_falls_back_to_the_vendored_one_when_nothing_is_installed() {
    # The machine this tool is usually rescuing has nothing installed, so the
    # vendored copy is a fallback rather than a mistake.
    _reset
    local root; root="$(mktemp -d)"; _fake_nutshell "$root/lib/nutshell"
    # A PATH with the ordinary tools on it and no nutshell, which is the
    # machine this is the fallback for.
    PATH="/usr/bin:/bin" nutshell_find "$root"
    local from="$NUTSHELL_FROM"
    rm -rf "$root"; _reset
    assert_eq "$from" "vendored"
}

#[test]
it_follows_a_launcher_that_is_a_link() {
    # The one on PATH is usually a link into a checkout, and the init sits
    # beside the binary rather than beside the link.
    _reset
    local d; d="$(mktemp -d)"; _fake_nutshell "$d/real"
    mkdir -p "$d/bin"; ln -s "$d/real/bin/nutshell" "$d/bin/nutshell"
    PATH="$d/bin:$PATH" nutshell_find ""
    local from="$NUTSHELL_FROM" init="$NUTSHELL_INIT"
    rm -rf "$d"; _reset
    assert_eq "$from" "installed"
    assert_contains "$init" "real"
}

#[test]
it_does_not_take_a_file_called_init_that_is_not_one() {
    # A tool with its own `init` would be sourced and would fail somewhere
    # less obvious than here.
    _reset
    local root; root="$(mktemp -d)"
    mkdir -p "$root/lib/nutshell"
    printf 'echo not nutshell\n' > "$root/lib/nutshell/init"
    local rc=0
    PATH="/usr/bin:/bin" nutshell_find "$root" 2>/dev/null || rc=$?
    rm -rf "$root"; _reset
    assert_ne "$rc" "0"
}

#[test]
it_fails_when_there_is_nothing_anywhere() {
    _reset
    local rc=0
    PATH="/usr/bin:/bin" nutshell_find "/no/such/root" 2>/dev/null || rc=$?
    _reset
    assert_ne "$rc" "0"
}

# --- refusing one that is too old --------------------------------------------

#[test]
it_accepts_a_version_that_is_new_enough() {
    NUTSHELL_VERSION="0.3.0" assert_ok nutshell_at_least "0.3.0"
    NUTSHELL_VERSION="0.4.0" assert_ok nutshell_at_least "0.3.0"
    NUTSHELL_VERSION="1.0.0" assert_ok nutshell_at_least "0.9.9"
}

#[test]
it_refuses_one_that_is_too_old() {
    local rc=0
    NUTSHELL_VERSION="0.2.9" nutshell_at_least "0.3.0" 2>/dev/null || rc=$?
    assert_ne "$rc" "0"
}

#[test]
it_compares_the_pieces_as_numbers() {
    # `0.10.0` is newer than `0.9.0`. A text compare says the opposite, and the
    # day that matters is the day the minor version reaches ten.
    NUTSHELL_VERSION="0.10.0" assert_ok nutshell_at_least "0.9.0"
    local rc=0
    NUTSHELL_VERSION="0.9.0" nutshell_at_least "0.10.0" 2>/dev/null || rc=$?
    assert_ne "$rc" "0"
}

#[test]
it_says_which_interpreter_it_was_complaining_about() {
    # The message has to name the copy, or somebody with two of them cannot
    # tell which one answered.
    NUTSHELL_INIT="/somewhere/init"; NUTSHELL_FROM="vendored"
    local out
    out="$(NUTSHELL_VERSION="0.1.0" nutshell_at_least "0.3.0" 2>&1 || true)"
    NUTSHELL_INIT=""; NUTSHELL_FROM=""
    assert_contains "$out" "0.1.0"
    assert_contains "$out" "0.3.0"
    assert_contains "$out" "/somewhere/init"
    assert_contains "$out" "vendored"
}

#[test]
it_asks_for_nothing_when_no_minimum_is_named() {
    NUTSHELL_VERSION="0.0.1" assert_ok nutshell_at_least ""
}

#[test]
it_finds_the_interpreter_with_nothing_on_the_path_at_all() {
    # This runs before anything is set up, on a machine that may be broken in
    # ways that include its PATH. A resolver needing a tool to find the
    # interpreter fails exactly when it is needed.
    _reset
    local root; root="$(mktemp -d)"; _fake_nutshell "$root/lib/nutshell"
    PATH="" nutshell_find "$root"
    local from="$NUTSHELL_FROM"
    rm -rf "$root"; _reset
    assert_eq "$from" "vendored"
}
