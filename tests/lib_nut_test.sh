#!/usr/bin/env bash
# Tests for the module declaration.
#
# The point of it is that a name either is in the tree or is not, answerable
# without running anything. Before it, a module was found by trying three
# layouts and taking whichever answered, so nothing could say in advance that a
# name would fail, and the failure arrived mid-run under `set -eo pipefail`
# with nothing to read.

use extern test

DECLARE="${BASH_SOURCE[0]%/*}/../bin/nut-declare"

# A library with a declaration, laid out the way a real one is.
_lib() {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/libs/tui" "$d/lib/json/impl"
    : > "$d/libs/tui/term.sh"
    : > "$d/libs/tui/key.sh"
    : > "$d/lib/json.sh"
    : > "$d/lib/json/impl/jq.sh"
    printf '%s\n' \
        'tui::term       libs/tui/term.sh' \
        'tui::key        libs/tui/key.sh' \
        'json            lib/json.sh' \
        'json::impl::jq  lib/json/impl/jq.sh  internal' \
        > "$d/lib.nut"
    printf '%s' "$d"
}

# --- resolution -----------------------------------------------------------------

#[test]
it_resolves_a_module_the_library_declares() {
    local d; d="$(_lib)"
    extern_path() { printf '%s' "$d"; }
    assert_eq "$(extern_resolve 'dep::tui::term')" "$d/libs/tui/term.sh"
    assert_eq "$(extern_resolve 'dep::json')"      "$d/lib/json.sh"
    unset -f extern_path; rm -rf "$d"
}

#[test]
it_refuses_a_module_the_library_does_not_declare() {
    local d; d="$(_lib)"
    # The file is there. It is still refused, because a declaration that a
    # search can go behind is not a declaration.
    mkdir -p "$d/libs/tui"; : > "$d/libs/tui/undeclared.sh"
    extern_path() { printf '%s' "$d"; }
    assert_fails extern_resolve 'dep::tui::undeclared'
    unset -f extern_path; rm -rf "$d"
}

#[test]
it_says_what_the_library_does_declare() {
    local d out; d="$(_lib)"
    extern_path() { printf '%s' "$d"; }
    out="$(extern_resolve 'dep::nope' 2>&1 || true)"
    assert_ok grep -qi 'not among the modules' <<<"$out"
    unset -f extern_path; rm -rf "$d"
}

#[test]
it_refuses_a_declaration_pointing_at_a_file_that_is_gone() {
    local d out; d="$(_lib)"
    rm -f "$d/libs/tui/key.sh"
    extern_path() { printf '%s' "$d"; }
    out="$(extern_resolve 'dep::tui::key' 2>&1 || true)"
    assert_fails extern_resolve 'dep::tui::key'
    # Named, so the fix is obvious: either the file moved or the line is stale.
    assert_ok grep -q 'which is not there' <<<"$out"
    unset -f extern_path; rm -rf "$d"
}

#[test]
it_keeps_an_internal_module_out_of_a_consumers_reach() {
    local d; d="$(_lib)"
    extern_path() { printf '%s' "$d"; }
    # Picked at runtime by the module above it. A consumer reaching it directly
    # is reaching past the thing whose job is to choose.
    assert_fails extern_resolve 'dep::json::impl::jq'
    unset -f extern_path; rm -rf "$d"
}

#[test]
it_still_refuses_a_slash_even_with_a_declaration() {
    local d; d="$(_lib)"
    extern_path() { printf '%s' "$d"; }
    assert_fails extern_resolve 'dep::tui/term'
    unset -f extern_path; rm -rf "$d"
}

#[test]
it_ignores_comments_and_blank_lines() {
    local d; d="$(_lib)"
    printf '\n# a comment\n\n' >> "$d/lib.nut"
    extern_path() { printf '%s' "$d"; }
    assert_eq "$(extern_resolve 'dep::json')" "$d/lib/json.sh"
    unset -f extern_path; rm -rf "$d"
}

# --- the migration ----------------------------------------------------------------

#[test]
it_declares_what_the_old_resolver_would_have_found() {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/libs/tui" "$d/lib"
    : > "$d/libs/tui/term.sh"; : > "$d/lib/log.sh"
    local out; out="$("$DECLARE" --print "$d")"
    # The names are the ones a `use` would have written for those files.
    assert_ok grep -qE '^tui::term[[:space:]]+libs/tui/term\.sh' <<<"$out"
    assert_ok grep -qE '^log[[:space:]]+lib/log\.sh' <<<"$out"
    rm -rf "$d"
}

#[test]
it_marks_an_implementation_file_internal() {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/lib/json/impl"
    : > "$d/lib/json/impl/jq.sh"
    assert_ok grep -q 'internal' <<<"$("$DECLARE" --print "$d")"
    rm -rf "$d"
}

#[test]
it_does_not_declare_a_vendored_nutshell_as_part_of_the_library() {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/lib/nutshell/lib" "$d/lib"
    : > "$d/lib/nutshell/lib/log.sh"; : > "$d/lib/own.sh"
    local out; out="$("$DECLARE" --print "$d")"
    assert_ok    grep -q 'own' <<<"$out"
    assert_fails grep -q 'nutshell' <<<"$(grep -v '^#' <<<"$out")"
    rm -rf "$d"
}

#[test]
it_never_overwrites_a_declaration_that_exists() {
    local d; d="$(_lib)"
    local before; before="$(cat "$d/lib.nut")"
    "$DECLARE" "$d" >/dev/null 2>&1
    assert_eq "$(cat "$d/lib.nut")" "$before"
    rm -rf "$d"
}

#[test]
it_shows_the_difference_rather_than_editing() {
    local d out; d="$(_lib)"
    : > "$d/libs/tui/extra.sh"
    out="$("$DECLARE" "$d" 2>&1)"
    assert_ok grep -q 'already exists' <<<"$out"
    assert_ok grep -q 'extra' <<<"$out"
    rm -rf "$d"
}

# --- the check --------------------------------------------------------------------

#[test]
it_passes_a_library_whose_declaration_matches_its_files() {
    local d; d="$(_lib)"
    assert_ok "$DECLARE" --check "$d"
    rm -rf "$d"
}

#[test]
it_catches_a_declaration_whose_file_is_missing() {
    local d out; d="$(_lib)"
    rm -f "$d/lib/json.sh"
    out="$("$DECLARE" --check "$d" 2>&1 || true)"
    assert_fails "$DECLARE" --check "$d"
    assert_ok grep -q 'declared but missing' <<<"$out"
    rm -rf "$d"
}

#[test]
it_catches_a_file_nothing_declares() {
    local d out; d="$(_lib)"
    : > "$d/libs/tui/orphan.sh"
    out="$("$DECLARE" --check "$d" 2>&1 || true)"
    assert_fails "$DECLARE" --check "$d"
    # The direction a search could never report: the file resolves fine, and
    # is reachable by a name the library never meant to offer.
    assert_ok grep -q 'present but undeclared' <<<"$out"
    rm -rf "$d"
}

#[test]
it_reports_a_library_with_no_declaration_at_all() {
    local d out; d="$(mktemp -d)"
    mkdir -p "$d/lib"; : > "$d/lib/one.sh"
    out="$("$DECLARE" --check "$d" 2>&1 || true)"
    assert_fails "$DECLARE" --check "$d"
    assert_ok grep -q 'has no lib.nut' <<<"$out"
    rm -rf "$d"
}

#[test]
it_checks_every_library_in_this_workspace() {
    # The declarations shipped here have to match the files shipped here, or
    # the check is a thing that only passes on fixtures.
    assert_ok "$DECLARE" --check "${BASH_SOURCE[0]%/*}/.."
}

#[test]
it_finds_a_module_however_deep_it_sits() {
    # The scan used a glob per level, so a module one level deeper than anyone
    # had written a glob for was invisible. Invisible to --check too, since
    # both read the same list: the library reported complete while
    # text::impl::combo::grep_sed was undeclared and would have failed at the
    # moment it was reached.
    local d; d="$(mktemp -d)"
    mkdir -p "$d/lib/text/impl/combo"
    : > "$d/lib/text/impl/combo/grep_sed.sh"
    local out; out="$("$DECLARE" --print "$d")"
    assert_ok grep -q 'text::impl::combo::grep_sed' <<<"$out"
    rm -rf "$d"
}

#[test]
it_finds_one_deeper_still() {
    # Not "one more level than the bug had": no level at all.
    local d; d="$(mktemp -d)"
    mkdir -p "$d/lib/a/b/c/d/e"
    : > "$d/lib/a/b/c/d/e/deep.sh"
    assert_ok grep -q 'a::b::c::d::e::deep' <<<"$("$DECLARE" --print "$d")"
    rm -rf "$d"
}

#[test]
it_reports_a_deep_file_as_undeclared() {
    # The check has to see as far as the scan, or it certifies a tree it did
    # not look at.
    local d out; d="$(mktemp -d)"
    mkdir -p "$d/lib/a/b/c"
    : > "$d/lib/a/b/c/deep.sh"
    printf 'nothing lib/nothing.sh\n' > "$d/lib.nut"
    : > "$d/lib/nothing.sh"
    out="$("$DECLARE" --check "$d" 2>&1 || true)"
    assert_ok grep -q 'a::b::c::deep' <<<"$out"
    rm -rf "$d"
}

#[test]
it_loads_an_implementation_through_the_resolver() {
    # A hand-rolled `source` goes around the resolver: loaded again for every
    # caller, not covered by the declaration, and failing when reached rather
    # than before the run.
    local bad=""
    grep -rn 'source "\${_[A-Z_]*_DIR}' "${BASH_SOURCE[0]%/*}/../lib"/*.sh 2>/dev/null \
        | grep -v '/nutshell/' | while IFS= read -r line; do
        printf '%s\n' "$line"
    done > /tmp/_nut_direct_sources.$$
    bad="$(cat /tmp/_nut_direct_sources.$$)"; rm -f /tmp/_nut_direct_sources.$$
    assert_empty "$bad"
}
