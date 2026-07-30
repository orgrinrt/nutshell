#!/usr/bin/env bash
# Tests for external libraries and the lockfile.
#
# Against a repository made here, reached by a file:// url, so the suite does
# not depend on a network or on somebody else's history staying put. git treats
# a local url the same as a remote one for everything these tests exercise.

use extern test fs

# _extern_fixture -> prints "<workdir> <first-commit> <second-commit>"
#
# A project directory with a nut.toml, and a dependency repository with two
# commits, so a test can pin to the older one and see whether it is obeyed.
_extern_fixture() {
    local work dep first second
    work="$(fs_temp_dir nutshell-extern)"
    dep="${work}/dep"

    mkdir -p "${dep}/lib"
    git -C "$dep" init --quiet -b main 2>/dev/null || { mkdir -p "$dep" && git -C "$dep" init --quiet; }
    git -C "$dep" config user.email t@example.com
    git -C "$dep" config user.name Test

    printf 'greet() { printf hello; }\n' > "${dep}/lib/greet.sh"
    git -C "$dep" add -A && git -C "$dep" commit --quiet -m first
    first="$(git -C "$dep" rev-parse HEAD)"

    printf 'greet() { printf goodbye; }\n' > "${dep}/lib/greet.sh"
    git -C "$dep" add -A && git -C "$dep" commit --quiet -m second
    second="$(git -C "$dep" rev-parse HEAD)"

    mkdir -p "${work}/project"
    cat > "${work}/project/nut.toml" <<TOML
[deps.fixture]
git = "file://${dep}"
ref = "main"
TOML

    printf '%s %s %s' "$work" "$first" "$second"
}

# Each test gets its own cache root, so one test's checkout is not another's.
_isolate() {
    XDG_CACHE_HOME="$(fs_temp_dir nutshell-extern-cache)"
    export XDG_CACHE_HOME
}

#[test]
it_resolves_a_declared_dependency() {
    _isolate
    local fix work
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    assert_contains "$(extern_declared fixture)" "file://"
}

#[test]
it_refuses_a_dependency_the_manifest_does_not_declare() {
    _isolate
    local fix work
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    assert_fails extern_declared nothing_here
}

#[test]
it_writes_the_resolved_commit_to_the_lockfile() {
    _isolate
    local fix work second
    fix="$(_extern_fixture)"; work="${fix%% *}"; second="${fix##* }"
    cd "${work}/project" || return 1

    extern_path fixture >/dev/null
    assert_eq "$(extern_locked fixture)" "$second" "the tip of main, recorded"
}

#[test]
it_holds_a_checkout_at_the_locked_commit() {
    # The point of the file. `ref = "main"` moves, so without this two checkouts
    # of one project can be running different code and neither can say so.
    _isolate
    local fix work first dir
    fix="$(_extern_fixture)"; work="${fix%% *}"
    first="$(printf '%s' "$fix" | cut -d' ' -f2)"
    cd "${work}/project" || return 1

    extern_lock_write fixture "$first"
    dir="$(extern_path fixture)"

    assert_eq "$(git -C "$dir" rev-parse HEAD)" "$first"
    assert_contains "$(cat "${dir}/lib/greet.sh")" "hello"
}

#[test]
it_refuses_a_commit_the_remote_does_not_have() {
    # Silently taking the tip instead would defeat the lock at the one moment
    # it matters.
    _isolate
    local fix work
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    extern_lock_write fixture "0000000000000000000000000000000000000000"
    assert_fails extern_path fixture
}

#[test]
it_keeps_the_other_entries_when_one_is_written() {
    _isolate
    local fix work
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    extern_lock_write other "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    extern_lock_write fixture "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    assert_eq "$(extern_locked other)" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    assert_eq "$(extern_locked fixture)" "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}

#[test]
it_gives_two_projects_locked_apart_their_own_checkouts() {
    # The case the pin exists for, and the one every other test here hides by
    # giving itself a private cache. The cache is shared on purpose, so two
    # projects naming one repository meet in it.
    #
    # With a single checkout per url and ref they took turns checking it out
    # under each other: each got the commit it asked for at the moment it
    # asked, and then read files from a directory the other had since moved.
    _isolate
    local fix work first second dep
    fix="$(_extern_fixture)"
    work="${fix%% *}"
    first="$(printf '%s' "$fix" | cut -d' ' -f2)"
    second="${fix##* }"
    dep="${work}/dep"

    # Two projects, one shared cache, one repository, different locks.
    mkdir -p "${work}/other"
    cp "${work}/project/nut.toml" "${work}/other/nut.toml"

    local dir_a dir_b
    cd "${work}/project" || return 1
    extern_lock_write fixture "$first"
    dir_a="$(extern_path fixture)"

    cd "${work}/other" || return 1
    extern_lock_write fixture "$second"
    dir_b="$(extern_path fixture)"

    assert_ne "$dir_a" "$dir_b" "a checkout per commit, not per ref"
    assert_contains "$(cat "${dir_a}/lib/greet.sh")" "hello"
    assert_contains "$(cat "${dir_b}/lib/greet.sh")" "goodbye"
}

#[test]
it_fetches_one_repository_once_for_two_projects() {
    # The reason the cache is shared at all. Two projects on the same ref share
    # the fetch; only the checkout is per commit.
    _isolate
    local fix work
    fix="$(_extern_fixture)"; work="${fix%% *}"
    mkdir -p "${work}/other"
    cp "${work}/project/nut.toml" "${work}/other/nut.toml"

    cd "${work}/project" || return 1
    extern_path fixture >/dev/null

    cd "${work}/other" || return 1
    local out
    out="$(extern_path fixture 2>&1 >/dev/null)"
    assert_empty "$out" "the second project fetches nothing"
}

#[test]
it_survives_four_processes_resolving_at_once() {
    # The shared cache makes this the ordinary case, not a corner. Four of them
    # on a cold cache had three fail with "could not fetch", because git was
    # cloning into a directory another clone was already populating.
    _isolate
    local fix work i rc=0
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    local -a pids=()
    for i in 1 2 3 4; do
        bash -c '. "$1"/init; use extern; extern_path fixture >/dev/null 2>&1' \
            _ "$NUTSHELL_ROOT" &
        pids+=($!)
    done
    for i in "${pids[@]}"; do
        wait "$i" || rc=1
    done

    assert_eq "$rc" "0" "every one of four concurrent resolutions succeeded"
}

#[test]
it_relays_out_a_checkout_whose_mirror_is_gone() {
    # A worktree whose mirror has been deleted is still a directory. Returning
    # it handed the caller a path git refuses to answer any question about,
    # permanently, with nothing to do but find the cache by hand.
    _isolate
    local fix work dir
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    extern_path fixture >/dev/null
    rm -rf "$(_extern_cache_root)"/mirror-*

    dir="$(extern_path fixture)"
    assert_ok git -C "$dir" rev-parse --git-dir
}

#[test]
it_repairs_a_mirror_left_without_a_repository() {
    # An interrupted fetch leaves a directory that is not a checkout. The guard
    # skipped the work because the path existed, and the empty directory it
    # stopped for was exactly the thing that needed repairing, so every later
    # call failed and nothing ever fixed it.
    _isolate
    local fix work mirror
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    extern_path fixture >/dev/null
    mirror="$(printf '%s\n' "$(_extern_cache_root)"/mirror-*)"
    rm -rf "${mirror}/.git"

    assert_ok extern_path fixture
    assert_ok git -C "$(extern_path fixture)" rev-parse --git-dir
}

#[test]
it_makes_a_waiter_wait_for_a_finished_checkout() {
    # The waiter returned as soon as the directory appeared, which is when the
    # winner is still writing into it, so a caller could be handed a path with
    # nothing in it yet.
    _isolate
    local fix work dir lock
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    # Stand where a winner would: the lock held, the target present but not a
    # checkout. A waiter must not take that for done.
    dir="$(_extern_cache_root)/pretend"
    fs_mkdir "$dir"
    lock="${dir}.lock"
    fs_mkdir "$lock"

    # It cannot return 0 here, so a short wait is enough to tell the two
    # answers apart: the old shape returned immediately.
    local rc=0
    _EXTERN_LOCK_WAIT_SECONDS=2 _extern_guard "$dir" true || rc=$?
    rmdir "$lock" 2>/dev/null

    assert_ne "$rc" "0" "an unfinished directory is not a finished one"
}

#[test]
it_takes_over_a_lock_whose_holder_died() {
    # An interrupted process leaves its lock behind, and before the holder's
    # pid lived in the lock the only way past it was to sit out a ten minute
    # clock. The wait here is capped at 3 seconds, so this passes only if the
    # dead holder's lock is reclaimed rather than waited on.
    _isolate
    local fix work dir lock corpse
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    dir="$(_extern_cache_root)/pretend"
    lock="${dir}.lock"
    fs_mkdir "$lock"
    bash -c ':' & corpse=$!
    wait "$corpse"
    printf '%s' "$corpse" > "${lock}/pid"

    local rc=0
    _EXTERN_LOCK_WAIT_SECONDS=3 _extern_guard "$dir" git init --quiet "$dir" || rc=$?

    assert_eq "$rc" "0" "a dead holder's lock is taken over, not waited out"
    assert_ok git -C "$dir" rev-parse --git-dir
}

#[test]
it_resolves_a_namespaced_module_to_a_file() {
    # What a namespaced `use` turns into. Kept separate from loading so the
    # resolution can be asked about without sourcing anything.
    _isolate
    local fix work
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    assert_contains "$(extern_resolve 'fixture::greet')" "/lib/greet.sh"
    assert_ok test -f "$(extern_resolve 'fixture::greet')"
}

#[test]
it_refuses_a_module_the_library_does_not_have() {
    _isolate
    local fix work
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    assert_fails extern_resolve 'fixture::nothing_here'
}

#[test]
it_refuses_a_spec_that_names_no_library() {
    # A bare name is nutshell's own module, not an extern's, so this must not
    # quietly resolve it against some library.
    _isolate
    assert_fails extern_resolve 'greet'
}

# -----------------------------------------------------------------------------
# Which nut.toml answers for a script
# -----------------------------------------------------------------------------
#
# A script's dependencies belong to the script, the way a crate's belong to its
# Cargo.toml. Resolving from the working directory alone meant a script run
# against another repository found that repository's manifest, or none, and
# never its own.

# _manifest_fixture -> prints "<root>"
#
# A unit directory holding a manifest and a script, a sibling with no manifest
# to be called from, and a project with a manifest of its own further down.
_manifest_fixture() {
    local root
    # Normalised through cd, because TMPDIR may carry a trailing slash and
    # fs_temp_dir passes it through, while a path that has been cd'd into comes
    # back single-slashed. Comparing one against the other fails on the slash
    # rather than on the behaviour.
    root="$(cd "$(fs_temp_dir nutshell-manifest)" && pwd)"
    mkdir -p "${root}/unit" "${root}/elsewhere" "${root}/project/sub" "${root}/loose"
    printf '[deps.a]\ngit = "x"\n' > "${root}/unit/nut.toml"
    printf '[deps.b]\ngit = "y"\n' > "${root}/project/nut.toml"
    printf '%s' "$root"
}

#[test]
it_prefers_the_scripts_own_manifest_over_the_working_directory() {
    local root
    root="$(_manifest_fixture)"
    cd "${root}/project/sub" || return 1

    NUTSHELL_SCRIPT_DIR="${root}/unit"
    assert_eq "$(_extern_manifest)" "${root}/unit/nut.toml" \
        "the script's own manifest wins over the one above the caller"
}

#[test]
it_falls_back_to_the_working_directory_when_the_script_has_no_manifest() {
    local root
    root="$(_manifest_fixture)"
    cd "${root}/project/sub" || return 1

    # A scratch script with no unit of its own: the project in front of it is
    # the right answer.
    NUTSHELL_SCRIPT_DIR="${root}/loose"
    assert_eq "$(_extern_manifest)" "${root}/project/nut.toml" \
        "no manifest above the script, so the caller's project answers"
}

#[test]
it_clears_inherited_script_identity_in_a_fresh_process() {
    # NUTSHELL_SCRIPT_DIR is exported for the interpreter's own script, so a
    # descendant that sources init directly would inherit an ancestor's value
    # and resolve that ancestor's manifest as its own. init unsets it; the
    # interpreter re-exports fresh values for the script it actually runs.
    local root out
    root="$(_manifest_fixture)"
    cd "${root}/project/sub" || return 1

    export NUTSHELL_SCRIPT_DIR="${root}/unit"
    out="$(bash -c '. "$1/init" && use extern >/dev/null 2>&1; _extern_manifest' _ "$NUTSHELL_ROOT")"

    assert_eq "$out" "${root}/project/nut.toml" \
        "an ancestor's script directory does not answer for a fresh process"
}

#[test]
it_still_resolves_from_the_working_directory_when_nothing_names_a_script() {
    local root
    root="$(_manifest_fixture)"
    cd "${root}/project/sub" || return 1

    # Sourced `init` rather than run through the interpreter, so the variable
    # is unset. The old behaviour has to keep working.
    unset NUTSHELL_SCRIPT_DIR
    assert_eq "$(_extern_manifest)" "${root}/project/nut.toml"
}
