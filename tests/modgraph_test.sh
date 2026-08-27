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

# --- the pub(super) rung -----------------------------------------------------

# The layout `modgraph_build` expects: it takes the lib directory and reads the
# manifest from its parent. And `MODGRAPH_NOCACHE`, or a second fixture with
# the same directory name would be answered from the first one's cache.
_mgs() {
    _MGS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nut-mgs.XXXXXX")"
    mkdir -p "$_MGS_DIR/lib/json/impl"
    printf '%s\n' "$@" > "$_MGS_DIR/lib.nut"
    export MODGRAPH_NOCACHE=1
}
_mgs_done() { rm -rf "$_MGS_DIR"; unset MODGRAPH_NOCACHE; }

#[test]
it_lets_any_module_above_call_a_pub_super_function() {
    # `super` is the rung between `lib` and private: every module above the
    # owner, and anything under the owner's immediate parent.
    #
    # Upward it is every ancestor rather than only the immediate parent, which
    # is what Rust means. Here the immediate parent is often not a module at
    # all: `json::impl` names no file, nothing can be written in it, and a
    # strict reading would make this rung unusable in the one layout it exists
    # for. `json` is what calls `json::impl::jq`, so `json` is the audience.
    _mgs 'json             lib/json.sh' 'json::impl::jq   lib/json/impl/jq.sh'
    cat > "$_MGS_DIR/lib/json/impl/jq.sh" <<'EOF'
#[pub(super)]
_jq_do() { :; }
EOF
    cat > "$_MGS_DIR/lib/json.sh" <<'EOF'
use json::impl::jq
json_get() {
    _jq_do
}
EOF
    modgraph_build "$_MGS_DIR/lib"
    assert_eq "$(modgraph_visibility _jq_do)" "super"
    assert_not_contains "$(modgraph_audit)" "private"
    _mgs_done
}

#[test]
it_lets_a_sibling_under_the_same_parent_call_it() {
    _mgs 'json             lib/json.sh' \
         'json::impl::jq   lib/json/impl/jq.sh' \
         'json::impl::perl lib/json/impl/perl.sh'
    cat > "$_MGS_DIR/lib/json/impl/jq.sh" <<'EOF'
#[pub(super)]
_jq_do() { :; }
EOF
    cat > "$_MGS_DIR/lib/json/impl/perl.sh" <<'EOF'
use json::impl::jq
_perl_do() {
    _jq_do
}
EOF
    printf 'json_get() { :; }\n' > "$_MGS_DIR/lib/json.sh"
    modgraph_build "$_MGS_DIR/lib"
    assert_not_contains "$(modgraph_audit)" "private"
    _mgs_done
}

#[test]
it_refuses_a_stranger_calling_a_pub_super_function() {
    # The whole point of the rung. Without this it would be `pub(lib)` under a
    # different name, and every one of these markers would mean nothing.
    _mgs 'json             lib/json.sh' \
         'json::impl::jq   lib/json/impl/jq.sh' \
         'text             lib/text.sh'
    cat > "$_MGS_DIR/lib/json/impl/jq.sh" <<'EOF'
#[pub(super)]
_jq_do() { :; }
EOF
    cat > "$_MGS_DIR/lib/text.sh" <<'EOF'
use json::impl::jq
text_go() {
    _jq_do
}
EOF
    printf 'json_get() { :; }\n' > "$_MGS_DIR/lib/json.sh"
    modgraph_build "$_MGS_DIR/lib"
    assert_contains "$(modgraph_audit)" "private"
    _mgs_done
}

#[test]
it_reports_a_pub_super_on_a_module_with_nothing_above_it() {
    # There is no super for it to be visible to, so the marker reads as public
    # and means private. Reported rather than silently treated as either.
    _mgs 'alone            lib/alone.sh' 'other            lib/other.sh'
    cat > "$_MGS_DIR/lib/alone.sh" <<'EOF'
#[pub(super)]
alone_do() { :; }
EOF
    cat > "$_MGS_DIR/lib/other.sh" <<'EOF'
use alone
other_go() {
    alone_do
}
EOF
    modgraph_build "$_MGS_DIR/lib"
    assert_contains "$(modgraph_audit)" "super_at_root"
    _mgs_done
}

#[test]
it_still_refuses_an_unmarked_function_to_everyone() {
    # The control. If `super` were being read as "visible", these tests would
    # pass against a rule that accepts anything.
    _mgs 'json             lib/json.sh' 'json::impl::jq   lib/json/impl/jq.sh'
    printf '_jq_do() { :; }\n' > "$_MGS_DIR/lib/json/impl/jq.sh"
    cat > "$_MGS_DIR/lib/json.sh" <<'EOF'
use json::impl::jq
json_get() {
    _jq_do
}
EOF
    modgraph_build "$_MGS_DIR/lib"
    assert_eq "$(modgraph_visibility _jq_do)" ""
    assert_contains "$(modgraph_audit)" "private"
    _mgs_done
}

#[test]
it_refuses_a_parent_reaching_into_a_childs_unmarked_function() {
    # The direction that stays closed. A child may reach up into its ancestors
    # without a marker, because it is part of them. A parent reaching down into
    # a child needs the child to export, or the split into two files would
    # quietly become one module with no boundary at all.
    _mgs 'toml         lib/toml.sh' 'toml::json   lib/toml/json.sh'
    mkdir -p "$_MGS_DIR/lib/toml"
    printf '_json_helper() {\n    :\n}\n' > "$_MGS_DIR/lib/toml/json.sh"
    cat > "$_MGS_DIR/lib/toml.sh" <<'EOF'
use toml::json
toml_get() {
    _json_helper
}
EOF
    modgraph_build "$_MGS_DIR/lib"
    assert_contains "$(modgraph_audit)" "private"
    _mgs_done
}

#[test]
it_lets_a_child_reach_its_own_ancestor_without_a_marker() {
    # The other direction. `toml::json` is `toml` written in a second file
    # because one file would be too long, and calling `toml`'s own helpers is
    # not reaching into a stranger. Two real findings in this library were
    # exactly this and were not defects.
    _mgs 'toml         lib/toml.sh' 'toml::json   lib/toml/json.sh'
    mkdir -p "$_MGS_DIR/lib/toml"
    printf '_toml_helper() {\n    :\n}\ntoml_get() {\n    :\n}\n' > "$_MGS_DIR/lib/toml.sh"
    cat > "$_MGS_DIR/lib/toml/json.sh" <<'EOF'
use super::toml
toml_to_json() {
    _toml_helper
}
EOF
    modgraph_build "$_MGS_DIR/lib"
    assert_not_contains "$(modgraph_audit)" "private"
    _mgs_done
}
