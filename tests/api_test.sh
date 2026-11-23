#!/usr/bin/env bash
# Tests for `nutshell api`, the lister of a library's public functions.
#
# The fixture library under fixtures/apilib is made to be listed: two public
# functions written out of order, one with no usage line, a private one, a
# module with nothing public and an internal module carrying a marker. Libraries
# named in a nut.toml are reached through a git repository made here by a file://
# url, so no test needs a network.

use test deps

ROOT_DIR="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
NUTSHELL="${ROOT_DIR}/bin/nutshell"
FIXLIB="${ROOT_DIR}/tests/fixtures/apilib"

_API_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-api.XXXXXX")"
trap 'rm -rf "$_API_TMP"' EXIT

# _api_repo -> prints the path of a git repository holding the fixture library
_api_repo() {
    local d; d="$(mktemp -d "${_API_TMP}/repo.XXXXXX")"
    cp -R "${FIXLIB}/." "$d/"
    git -C "$d" init --quiet -b main 2>/dev/null || git -C "$d" init --quiet
    git -C "$d" config user.email t@example.com
    git -C "$d" config user.name Test
    git -C "$d" add -A && git -C "$d" commit --quiet -m fixture
    printf '%s' "$d"
}

# _api_in <dir> <args...> -> nutshell api run from <dir>, with a private store
_api_in() {
    local dir="$1"; shift
    ( cd "$dir" && NUTSHELL_STORE="${_API_TMP}/store" \
        env -u NUTSHELL_SCRIPT_DIR -u _NUT_ASKING_FROM "$NUTSHELL" api "$@" )
}

_GREET_TEXT='greet
  greet_alpha <name> -> prints a greeting
  greet_bare
  greet_wave <name> -> prints a wave
  greet_zulu <name> -> prints a farewell'

#[test]
it_lists_the_toml_table_function_with_its_usage_line() {
    local out; out="$(cd "$ROOT_DIR" && "$NUTSHELL" api toml)"
    assert_contains "$out" 'toml_tables "file.toml" "products" -> prints products.0'
    assert_eq "$(printf '%s\n' "$out" | sed -n 1p)" "toml"
}

#[test]
it_lists_exactly_the_modules_with_a_public_function_and_no_internal_marker() {
    # The expected set comes from lib.nut rows and a grep for the marker, not
    # from the lister's own readers.
    local want got name file rest
    want="$(while read -r name file rest; do
        case "$name" in ''|'#'*) continue ;; esac
        case "$rest" in *internal*) continue ;; esac
        grep -q '^#\[pub\]' "${ROOT_DIR}/${file}" && printf '%s\n' "$name"
    done < "${ROOT_DIR}/lib.nut" | LC_ALL=C sort -u)"
    got="$(cd "$ROOT_DIR" && "$NUTSHELL" api | grep -v '^ ')"
    assert_eq "$got" "$want"
    assert_contains "$got" "toml"
    assert_not_contains "$got" "deps::state"
}

#[test]
it_prints_every_public_function_under_its_module_with_two_space_indent() {
    local out; out="$(cd "$ROOT_DIR" && "$NUTSHELL" api attr)"
    assert_contains "$out" '  attr_usage '
    assert_contains "$out" '  attr_find tests/string_test.sh test -> prints each #[test] function'
}

#[test]
it_lists_a_library_at_a_path_sorted_with_internal_and_empty_modules_left_out() {
    local out; out="$(_api_in "$_API_TMP" --path "$FIXLIB")"
    assert_eq "$out" "$_GREET_TEXT"
    assert_not_contains "$out" "fmt_hidden"
    assert_not_contains "$out" "quiet"
}

#[test]
it_prints_the_same_bytes_twice_so_a_listing_can_be_committed_and_diffed() {
    local a b
    a="$(_api_in "$_API_TMP" --path "$FIXLIB")"
    b="$(_api_in "$_API_TMP" --path "$FIXLIB")"
    assert_eq "$a" "$b"
    assert_eq "$(printf '%s\n' "$a" | sed -n 2p)" "  greet_alpha <name> -> prints a greeting"
}

#[test]
it_lists_one_module_of_a_library() {
    assert_eq "$(_api_in "$_API_TMP" --path "$FIXLIB" greet)" "$_GREET_TEXT"
}

#[test]
it_refuses_a_module_the_library_does_not_declare() {
    assert_fails _api_in "$_API_TMP" --path "$FIXLIB" nowhere
    assert_contains "$(_api_in "$_API_TMP" --path "$FIXLIB" nowhere 2>&1)" "nowhere"
}

#[test]
it_refuses_an_internal_module() {
    assert_fails _api_in "$_API_TMP" --path "$FIXLIB" greet::impl::fmt
    assert_contains "$(_api_in "$_API_TMP" --path "$FIXLIB" greet::impl::fmt 2>&1)" "internal"
}

#[test]
it_refuses_a_module_with_nothing_public() {
    assert_fails _api_in "$_API_TMP" --path "$FIXLIB" quiet
    assert_contains "$(_api_in "$_API_TMP" --path "$FIXLIB" quiet 2>&1)" "no public functions"
}

#[test]
it_prints_markdown_with_a_block_per_module() {
    local want
    want='# apilib

## greet

```
greet_alpha <name> -> prints a greeting
greet_bare
greet_wave <name> -> prints a wave
greet_zulu <name> -> prints a farewell
```'
    assert_eq "$(_api_in "$_API_TMP" --path "$FIXLIB" --md)" "$want"
}

#[test]
it_lists_a_library_named_in_the_nearest_nut_toml() {
    deps_has git || { skip "git is not on this machine"; return 0; }
    local repo proj
    repo="$(_api_repo)"
    proj="$(mktemp -d "${_API_TMP}/proj.XXXXXX")"
    printf '[deps.fixlib]\ngit = "file://%s"\nref = "main"\n' "$repo" > "${proj}/nut.toml"
    assert_eq "$(_api_in "$proj" --lib fixlib)" "$_GREET_TEXT"
}

#[test]
it_lists_a_library_through_a_manifest_above_the_working_directory() {
    deps_has git || { skip "git is not on this machine"; return 0; }
    local repo proj
    repo="$(_api_repo)"
    proj="$(mktemp -d "${_API_TMP}/proj.XXXXXX")"
    mkdir -p "${proj}/deep/er"
    printf '[deps.fixlib]\ngit = "file://%s"\n' "$repo" > "${proj}/nut.toml"
    assert_eq "$(_api_in "${proj}/deep/er" --lib fixlib greet)" "$_GREET_TEXT"
}

#[test]
it_refuses_a_library_the_manifest_does_not_name() {
    local proj; proj="$(mktemp -d "${_API_TMP}/proj.XXXXXX")"
    printf '[package]\nname = "x"\n' > "${proj}/nut.toml"
    assert_fails _api_in "$proj" --lib fixlib
    assert_contains "$(_api_in "$proj" --lib fixlib 2>&1)" "fixlib"
}

#[test]
it_lists_a_library_by_git_url_and_ref() {
    deps_has git || { skip "git is not on this machine"; return 0; }
    local repo plain
    repo="$(_api_repo)"
    plain="$(mktemp -d "${_API_TMP}/plain.XXXXXX")"
    assert_eq "$(_api_in "$plain" --git "file://${repo}" --ref main)" "$_GREET_TEXT"
}

#[test]
it_takes_the_default_branch_when_no_ref_is_given() {
    deps_has git || { skip "git is not on this machine"; return 0; }
    local repo plain
    repo="$(_api_repo)"
    plain="$(mktemp -d "${_API_TMP}/plain.XXXXXX")"
    assert_eq "$(_api_in "$plain" --git "file://${repo}" greet)" "$_GREET_TEXT"
}

#[test]
it_does_not_write_a_lockfile_for_a_url_listing() {
    deps_has git || { skip "git is not on this machine"; return 0; }
    local repo plain
    repo="$(_api_repo)"
    plain="$(mktemp -d "${_API_TMP}/plain.XXXXXX")"
    assert_eq "$(_api_in "$plain" --git "file://${repo}")" "$_GREET_TEXT"
    assert_fails test -e "${plain}/nut.lock"
}

#[test]
it_fails_on_a_url_that_cannot_be_fetched() {
    assert_fails _api_in "$_API_TMP" --git "file://${_API_TMP}/no-such-repo"
    assert_contains "$(_api_in "$_API_TMP" --git "file://${_API_TMP}/no-such-repo" 2>&1)" "no-such-repo"
}

#[test]
it_names_the_library_after_its_url_in_markdown_when_it_has_no_package_name() {
    deps_has git || { skip "git is not on this machine"; return 0; }
    local repo plain
    repo="$(_api_repo)"
    printf '' > "${repo}/nut.toml"
    git -C "$repo" add -A && git -C "$repo" commit --quiet -m "no name"
    plain="$(mktemp -d "${_API_TMP}/plain.XXXXXX")"
    assert_eq "$(_api_in "$plain" --git "file://${repo}" --md | sed -n 1p)" "# ${repo##*/}"
}

#[test]
it_refuses_two_library_sources_at_once() {
    assert_fails _api_in "$_API_TMP" --path "$FIXLIB" --git "file://${FIXLIB}"
    assert_contains "$(_api_in "$_API_TMP" --path "$FIXLIB" --git "file://${FIXLIB}" 2>&1)" "only one"
}

#[test]
it_refuses_an_unknown_flag() {
    assert_fails _api_in "$_API_TMP" --no-such-flag
    assert_contains "$(_api_in "$_API_TMP" --no-such-flag 2>&1)" "no-such-flag"
}

#[test]
it_lists_json_query_and_the_builders_under_json_from_its_internal_files() {
    # json::query and json::build are internal rows of lib.nut that json loads;
    # their functions are json's. The usage lines are the ones written above
    # each function in lib/json/query.sh and lib/json/build.sh.
    local out; out="$(cd "$ROOT_DIR" && "$NUTSHELL" api json)"
    assert_contains "$out" "  json_query '.items[] | .name' \"\$json\""
    assert_contains "$out" "  json_object \"key1\" \"value1\" \"key2\" \"value2\" -> '{"
    assert_contains "$out" "  json_array \"a\" \"b\" \"c\" -> '[\"a\""
    assert_eq "$(cd "$ROOT_DIR" && "$NUTSHELL" api | grep -c '^json::')" "0"
}

#[test]
it_lists_a_function_defined_in_the_module_and_an_internal_file_once() {
    # text.sh and text/impl/combo/grep_sed.sh both define and mark these.
    local out; out="$(cd "$ROOT_DIR" && "$NUTSHELL" api text)"
    assert_eq "$(printf '%s\n' "$out" | grep -c '^  text_filtered_replace ')" "1"
    assert_eq "$(printf '%s\n' "$out" | grep -c '^  text_count_in_matches ')" "1"
}

#[test]
it_lists_an_internal_module_no_module_loads_under_nothing() {
    local out; out="$(_api_in "$_API_TMP" --path "$FIXLIB")"
    assert_not_contains "$out" "fmt_hidden"
    assert_contains "$out" "  greet_wave <name> -> prints a wave"
    assert_not_contains "$out" "greet::wave"
}

#[test]
it_says_in_its_help_that_internal_files_list_under_their_module() {
    local out; out="$("$NUTSHELL" api --help)"
    assert_contains "$out" "internal"
}
