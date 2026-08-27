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
ROOT_DIR="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

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

# --- the ways around the declaration ------------------------------------------------
#
# A declaration a caller can step around is not a declaration. These are the
# routes that existed: a bare `use` went straight to lib/<name>.sh, so spelling
# a path reached a file the library had marked internal, in one call, without
# the declaration being consulted at all.

#[test]
it_refuses_a_bare_use_that_spells_a_path() {
    local out
    out="$(bash -c "cd '$ROOT_DIR'; . ./init; use json/impl/jq" 2>&1 || true)"
    assert_ok grep -q "separates modules with '/'" <<<"$out"
    assert_ok grep -q 'json::impl::jq' <<<"$out"
}

#[test]
it_does_not_load_an_internal_module_by_spelling_its_path() {
    local out
    out="$(bash -c "cd '$ROOT_DIR'; . ./init; use json/impl/jq >/dev/null 2>&1; declare -F _json_jq_get >/dev/null && printf REACHED || printf refused" 2>&1)"
    assert_ok grep -q 'refused' <<<"$out"
}

#[test]
it_still_loads_a_plain_module_by_name() {
    local out
    out="$(bash -c "cd '$ROOT_DIR'; . ./init; use json && printf OK" 2>&1)"
    assert_ok grep -q 'OK' <<<"$out"
}

#[test]
it_loads_its_own_nested_module_by_name() {
    # nutshell's own tree is named the way anybody else's is. Treating every
    # `::` as a dependency made its own nested modules unreachable except from
    # inside the unit.
    local out
    out="$(bash -c "cd '$ROOT_DIR'; . ./init; use text::impl::grep_match && printf OK" 2>&1)"
    assert_ok grep -q 'OK' <<<"$out"
}

# --- the ways a declaration was quietly wrong -----------------------------------------

#[test]
it_declares_a_module_flat_at_the_library_root() {
    # The resolver tries three layouts and the scan walked two, so a module at
    # the root resolved before the migration and was refused after it, with
    # --check certifying the drop because it reads the same scan.
    local d; d="$(mktemp -d)"
    mkdir -p "$d/lib"; : > "$d/helper.sh"; : > "$d/lib/other.sh"
    local out; out="$("$DECLARE" --print "$d")"
    assert_ok grep -qE '^helper[[:space:]]+helper\.sh' <<<"$out"
    assert_ok grep -qE '^other[[:space:]]+lib/other\.sh' <<<"$out"
    rm -rf "$d"
}

#[test]
it_refuses_to_declare_when_two_files_answer_to_one_name() {
    local d out; d="$(mktemp -d)"
    mkdir -p "$d/lib" "$d/libs"
    printf 'WHICH=lib\n'  > "$d/lib/dup.sh"
    printf 'WHICH=libs\n' > "$d/libs/dup.sh"
    # Writing one of them freezes a precedence and hides the other file for
    # good. Better to say so than to pick.
    out="$("$DECLARE" "$d" 2>&1 || "$DECLARE" "$d" 2>&1)"
    assert_ok grep -q 'same name' <<<"$out"
    assert_fails test -f "$d/lib.nut"
    rm -rf "$d"
}

#[test]
it_reports_two_files_answering_to_one_name_in_a_check() {
    local d out; d="$(mktemp -d)"
    mkdir -p "$d/lib" "$d/libs"
    : > "$d/lib/dup.sh"; : > "$d/libs/dup.sh"
    printf 'dup lib/dup.sh\n' > "$d/lib.nut"
    out="$("$DECLARE" --check "$d" 2>&1 || true)"
    assert_ok grep -q 'one name' <<<"$out"
    rm -rf "$d"
}

#[test]
it_keeps_the_last_declaration_when_the_file_has_no_trailing_newline() {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/lib"; : > "$d/lib/last.sh"
    printf 'last lib/last.sh' > "$d/lib.nut"      # no newline
    # An editor that trims the last newline would otherwise delete a module,
    # and the checker agreed because it read the file another way.
    assert_ok bash -c ". '$ROOT_DIR/init'; _lib_nut_lookup '$d' last"
    rm -rf "$d"
}

#[test]
it_reports_a_line_that_is_not_a_declaration() {
    local d out; d="$(mktemp -d)"
    printf 'nofile\n' > "$d/lib.nut"
    out="$("$DECLARE" --check "$d" 2>&1 || true)"
    # Rather than a raw bash error about an unset positional under set -u.
    assert_ok    grep -q 'not a declaration' <<<"$out"
    assert_fails grep -qi 'unbound\|bad substitution' <<<"$out"
    rm -rf "$d"
}

#[test]
it_reports_a_visibility_it_does_not_understand() {
    local d out; d="$(mktemp -d)"
    mkdir -p "$d/lib"; : > "$d/lib/x.sh"
    printf 'x lib/x.sh publicish\n' > "$d/lib.nut"
    out="$("$DECLARE" --check "$d" 2>&1 || true)"
    # A typo in a trailing column silently made an internal module public.
    #
    # "word" rather than "visibility": a trailing column can be a visibility or
    # a `when=` predicate now, and calling every one of them a visibility told
    # a reader with a mistyped predicate to look at the wrong thing.
    assert_ok grep -q 'unknown word' <<<"$out"
    rm -rf "$d"
}

#[test]
it_reports_a_gate_it_does_not_understand() {
    # A gate `_nut_gate` refuses is a variant that silently never loads, and
    # the row looks fine. Caught here it is a typo somebody can see.
    local d out; d="$(mktemp -d)"
    mkdir -p "$d/lib"; : > "$d/lib/x.sh"
    printf '#[shel(bash4)]\nx lib/x.sh\n' > "$d/lib.nut"
    out="$("$DECLARE" --check "$d" 2>&1 || true)"
    assert_ok grep -q 'unknown gate' <<<"$out"
    rm -rf "$d"
}

#[test]
it_accepts_every_gate_the_resolver_knows() {
    # The control. A validator rejecting everything would pass the test above
    # and refuse every real manifest.
    local d out rc; d="$(mktemp -d)"
    mkdir -p "$d/lib"; : > "$d/lib/x.sh"
    {
        printf '#[shell(bash4)]\nx lib/x.sh\n'
        printf '#[shell(bash)]\ny lib/x.sh\n'
        printf '#[has(bin(grep))]\nz lib/x.sh\n'
        printf '#[has(env(HOME))]\nw lib/x.sh\n'
    } > "$d/lib.nut"
    rc=0; out="$("$DECLARE" --check "$d" 2>&1)" || rc=$?
    assert_eq "$rc" "0" "$out"
    rm -rf "$d"
}

#[test]
it_skips_an_indented_comment_the_way_the_resolver_does() {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/lib"; : > "$d/lib/x.sh"
    printf '   # indented\nx lib/x.sh\n' > "$d/lib.nut"
    assert_ok "$DECLARE" --check "$d"
    rm -rf "$d"
}

#[test]
it_compares_a_module_name_as_a_word_not_as_a_pattern() {
    local d out; d="$(mktemp -d)"
    mkdir -p "$d/lib"
    : > "$d/lib/fs.impl.sh"
    printf 'fsXimpl lib/other.sh\n' > "$d/lib.nut"
    : > "$d/lib/other.sh"
    out="$("$DECLARE" --check "$d" 2>&1 || true)"
    # `fs.impl` as a regex matches `fsXimpl`, and the module would be reported
    # as declared when nothing declares it.
    assert_ok grep -q 'present but undeclared: fs.impl' <<<"$out"
    rm -rf "$d"
}

#[test]
it_loads_a_symlinked_module_once() {
    # A logical path leaves a link and its target as two keys, so one file
    # loads twice. Written to a file: the escaping needed to build this inside
    # a -c inside a test is its own source of bugs.
    local f; f="$(mktemp)"
    cat > "$f" <<'PROBE'
cd "$NUT_ROOT"
. ./init
a=$(mktemp -d); mkdir -p "$a/libs"
printf 'COUNT=$(( ${COUNT:-0} + 1 ))
' > "$a/libs/real.sh"
ln -s real.sh "$a/libs/alias.sh"
printf 'real libs/real.sh
alias libs/alias.sh
' > "$a/lib.nut"
use extern
extern_path() { printf '%s' "$a"; }
use dep::real
use dep::alias
printf 'COUNT=%s
' "$COUNT"
rm -rf "$a"
PROBE
    local out; out="$(NUT_ROOT="$ROOT_DIR" bash "$f" 2>&1)"
    rm -f "$f"
    assert_ok grep -q 'COUNT=1' <<<"$out"
}
