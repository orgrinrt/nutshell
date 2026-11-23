#!/usr/bin/env bash
# Tests for the tree the toml floor keeps between processes.
#
# Reading a 332-line manifest in bash takes about 37ms, and the interpreter and
# `deps` both read one before a script's first line: the engine pin and the
# `[deps.paths]` pins. A process keeps the tree it parsed, so what is cached
# here is the parse across processes, keyed by the file's text: a file whose
# text changed is parsed again, whatever its mtime says.
#
# Each process is a fresh bash under `env -i`, with its own cache directory, so
# nothing the test process holds reaches it. Each reads through the floor
# alone, `_TOML_FLOOR_ONLY`, since the floor is what keeps the tree; a tool's
# JSON is read again by the tool.

use test

INIT="${BASH_SOURCE[0]%/*}/../init"

_tc_fresh() {
    _TC_D="$(mktemp -d "${TMPDIR:-/tmp}/nut-tomlcache.XXXXXX")"
    printf '[package]\nname = "first"\n\n[deps.paths]\njq = "/opt/jq"\n' > "$_TC_D/nut.toml"
}

# _tc_read <key> [prelude] -> what `toml_get` printed, and stderr, in a new process
_tc_read() {
    env -i HOME="$HOME" PATH="$PATH" XDG_CACHE_HOME="${_TC_CACHE:-$_TC_D/cache}" \
        bash -c '. "$1" || exit 1; use toml; _TOML_FLOOR_ONLY=1; eval "$3"; toml_get "$2/nut.toml" "$4"' \
        _ "$INIT" "$_TC_D" "${2:-}" "$1" 2>&1
}

# A parse that says it ran, so a process answered from the kept tree is told
# apart from one that read the file again.
_TC_CANARY='_toml_parse_text() { printf "parsed "; _TOML_ERR="canary"; return 2; }'

#[test]
it_answers_a_second_process_from_the_tree_the_first_kept() {
    _tc_fresh
    local first second
    first="$(_tc_read package.name)"
    second="$(_tc_read package.name "$_TC_CANARY")"
    rm -rf "$_TC_D"
    assert_eq "$first" "first"
    assert_eq "$second" "first"
}

#[test]
it_parses_a_file_whose_text_changed_since_the_tree_was_kept() {
    # The positive control for the one above: the canary fires where there is
    # no kept tree for this text, so its silence there means something.
    _tc_fresh
    _tc_read package.name >/dev/null
    printf '[package]\nname = "second"\n' > "$_TC_D/nut.toml"
    local canary fresh
    canary="$(_tc_read package.name "$_TC_CANARY")"
    fresh="$(_tc_read package.name)"
    rm -rf "$_TC_D"
    assert_contains "$canary" "parsed"
    assert_eq "$fresh" "second"
}

#[test]
it_reads_the_file_where_the_cache_cannot_be_written() {
    _tc_fresh
    # A file where the directory would go, so nothing can be made under it.
    printf 'x' > "$_TC_D/cache"
    local out; out="$(_tc_read deps.paths.jq)"
    rm -rf "$_TC_D"
    assert_eq "$out" "/opt/jq"
}

#[test]
it_keeps_the_answers_of_a_table_and_an_array_through_the_cache() {
    # The tree is the whole tree, not the value asked for first: a second
    # process reading another key of the kept file gets that key.
    _tc_fresh
    printf '[a]\nlist = [1, 2, 3]\n[a.b]\n"k.d" = "dotted"\n' >> "$_TC_D/nut.toml"
    _tc_read package.name >/dev/null
    local list dotted
    list="$(_tc_read a.list "$_TC_CANARY")"
    dotted="$(_tc_read 'a.b."k.d"' "$_TC_CANARY")"
    rm -rf "$_TC_D"
    assert_eq "$list" "[1, 2, 3]"
    assert_eq "$dotted" "dotted"
}
