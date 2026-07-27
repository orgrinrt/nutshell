#!/usr/bin/env bash
# Tests for the module graph.
#
# Built against a fixture library rather than nutshell's own lib/, so the
# assertions stay true as nutshell changes. A test pinned to the real library
# breaks whenever a module is added, which teaches everyone to ignore it.

use modgraph test

FIXTURE="${BASH_SOURCE[0]%/*}/fixtures/lib"

#[test]
it_finds_every_module() {
    MODGRAPH_NOCACHE=1 modgraph_build "$FIXTURE"
    assert_eq "$(modgraph_modules | sort | tr '\n' ' ')" "alpha beta cyclic_a cyclic_b "
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
