#!/usr/bin/env bash
# Tests for the module graph.
#
# Built against a fixture library rather than nutshell's own lib/, so the
# assertions stay true as nutshell changes. A test pinned to the real library
# breaks whenever a module is added, which teaches everyone to ignore it.

use modgraph test fs

FIXTURE="${BASH_SOURCE[0]%/*}/fixtures/lib"

#[test]
it_finds_every_module() {
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    assert_eq "$(modgraph_modules | sort | tr '\n' ' ')" "alpha beta cyclic_a cyclic_b idle subst "
}

#[test]
it_records_what_a_module_declares() {
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    assert_contains "$(modgraph_declares beta)" "alpha"
}

#[test]
it_knows_which_module_defines_a_function() {
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    assert_eq "$(modgraph_owner alpha_public)" "alpha"
}

#[test]
it_records_visibility_from_the_attribute() {
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    assert_eq "$(modgraph_visibility alpha_public)" "pub"
    assert_empty "$(modgraph_visibility alpha_private)"
}

#[test]
it_does_not_mistake_a_local_variable_for_a_call() {
    # `beta` assigns a local named `alpha_private`. A scanner counting every
    # module-prefixed token, rather than tokens in command position, read that
    # as a call into alpha and reported a visibility violation that was really
    # a variable name.
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    assert_fails grep -q "alpha_private" <<< "$(modgraph_calls beta)"
}

#[test]
it_reports_a_cycle_as_a_path() {
    # The route, not the bare fact, so a reader can see which edge to cut.
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    assert_contains "$(modgraph_cycle)" "cyclic_a"
    assert_contains "$(modgraph_cycle)" "cyclic_b"
}

#[test]
it_reports_an_undeclared_cross_module_call() {
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    assert_contains "$(modgraph_audit)" "undeclared"
}

#[test]
it_reads_a_cached_graph_back_unchanged() {
    # The cache used to write one record per module with four tab-separated
    # fields. Tab is an IFS whitespace character, so bash collapses a run of
    # them: a module declaring nothing wrote two tabs, `read` saw one, and
    # every field after shifted left. The graph came back with each module's
    # defines sitting in its declares, so a cached run reported a clean
    # library while a fresh run reported the truth.
    #
    # `alpha` declares nothing, which is the case that triggered it.
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    local fresh_declares="${_MG_DECLARES[alpha]:-}"
    local fresh_calls="${_MG_CALLS[alpha]:-}"

    modgraph_build "$FIXTURE"   # writes the cache
    modgraph_build "$FIXTURE"   # reads it back

    assert_eq "${_MG_DECLARES[alpha]:-}" "$fresh_declares" "declares survived the round trip"
    assert_eq "${_MG_CALLS[alpha]:-}" "$fresh_calls" "calls survived the round trip"
    assert_eq "$(modgraph_owner alpha_public)" "alpha"
    assert_eq "$(modgraph_visibility alpha_public)" "pub"
}

#[test]
it_finds_the_same_violations_cached_as_fresh() {
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    local fresh
    fresh="$(modgraph_audit | sort)"

    modgraph_build "$FIXTURE"
    modgraph_build "$FIXTURE"

    assert_eq "$(modgraph_audit | sort)" "$fresh" "the cache changes speed, not answers"
}

#[test]
it_sees_a_call_made_through_process_substitution() {
    # `done < <(alpha_public)` is a call. The scanner split on `$(`, on `;`,
    # `|`, `&` and backtick, and not on `<(`, so a module reaching into another
    # only that way recorded no calls and passed the contract check untouched.
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    assert_contains "$(modgraph_calls subst)" "alpha_public"
}

#[test]
it_keeps_two_libraries_cache_apart() {
    # The cache path was the fingerprint of the files alone, so two libraries
    # whose files share names, sizes and modification times resolved to one
    # file and each read the other's graph.
    # `cp -p`, keeping the modification times. Without it the copies carry
    # fresh mtimes, the fingerprints differ on that alone, and the test passes
    # whether the directory is part of the key or not: it was green with the
    # `dir:` line deleted.
    local other
    other="$(fs_temp_dir nutshell-mg)"
    cp -p "$FIXTURE"/*.sh "$other/"

    modgraph_build "$FIXTURE"
    local a="${_MG_ROOT}"
    modgraph_build "$other"

    assert_ne "$(_mg_cache_file "$a")" "$(_mg_cache_file "$other")"
}

#[test]
it_reports_a_declaration_nothing_uses() {
    # `beta` declares `alpha` and does call into it, so the fixture needs a
    # module that declares and does not call. `subst` declares `alpha` and
    # calls it through process substitution, which is a call.
    #
    # Reported, never failed: a module can depend on another for a variable it
    # sets or for what it does when loaded, and neither shows up as a call.
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    assert_contains "$(modgraph_audit)" "unused	idle	alpha"
}

# --- two files, one module ---------------------------------------------------
#
# A `when=` row means a module is written twice, once for bash and once for
# POSIX sh, and only one is ever loaded. Named from the path, the second
# becomes a module of its own that calls everything the first defines and
# declares none of it, and the contract check reports every function.
#
# Fifteen of those on `string` the day the floor was added.

_mgv_lib() {
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-mgv.XXXXXX")"
    mkdir -p "$d/lib"
    printf '%s' "$1" > "$d/lib.nut"
    printf 'nut_once || return 0\n#[pub]\n# Usage: thing_do\nthing_do() { :; }\n' > "$d/lib/thing.sh"
    printf 'nut_once || return 0\n#[pub]\n# Usage: thing_do\nthing_do() { :; }\n' > "$d/lib/thing.posix.sh"
    printf '%s' "$d"
}

#[test]
it_reads_two_variant_files_as_one_module() {
    local d; d="$(_mgv_lib 'thing  lib/thing.sh        when=shell:bash4
thing  lib/thing.posix.sh')"
    MODGRAPH_ROOT="$d" modgraph_build "$d/lib"
    local mods; mods="$(printf '%s\n' "${_MG_MODULES[@]}" | sort | tr '\n' ' ')"
    assert_eq "$mods" "thing "
    unset MODGRAPH_ROOT
    rm -rf "$d"
}

#[test]
it_reports_no_undeclared_call_between_two_variants() {
    # The property that matters, rather than the module count: one spelling
    # must not read as calling into the other.
    local d; d="$(_mgv_lib 'thing  lib/thing.sh        when=shell:bash4
thing  lib/thing.posix.sh')"
    MODGRAPH_ROOT="$d" modgraph_build "$d/lib"
    assert_empty "$(modgraph_audit | grep undeclared || true)"
    unset MODGRAPH_ROOT
    rm -rf "$d"
}

#[test]
it_still_reads_two_unrelated_files_as_two_modules() {
    # The control. Merging on the file stem, or merging everything, would pass
    # both tests above and collapse the whole graph into one node.
    local d; d="$(_mgv_lib 'thing  lib/thing.sh
other  lib/thing.posix.sh')"
    MODGRAPH_ROOT="$d" modgraph_build "$d/lib"
    local mods; mods="$(printf '%s\n' "${_MG_MODULES[@]}" | sort | tr '\n' ' ')"
    assert_eq "$mods" "other thing "
    unset MODGRAPH_ROOT
    rm -rf "$d"
}

#[test]
it_names_a_file_the_manifest_does_not_mention_by_its_stem() {
    # What every file did before there was a manifest to ask, and what a file
    # outside one still gets.
    local d; d="$(_mgv_lib 'thing  lib/thing.sh')"
    assert_eq "$(_mg_module_of "$d/lib/thing.posix.sh" "$d")" "thing.posix"
    assert_eq "$(_mg_module_of "$d/lib/thing.sh" "$d")" "thing"
    assert_eq "$(_mg_module_of "/tmp/nowhere/zzz.sh" "$d")" "zzz"
    rm -rf "$d"
}
