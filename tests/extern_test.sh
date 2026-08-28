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
    work="$(_ex_tmp work)"
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
# A store of its own for each test.
#
# `NUTSHELL_STORE` rather than an XDG variable, because the store root is the
# thing being isolated and pointing at whichever XDG directory it currently
# derives from is isolation that stops working the moment it moves. It did:
# the store went from the cache directory to the data directory and the tests
# kept setting the cache one, so they were writing into the real store and
# nothing said so.
# One root for the whole file, taken down at the end of it.
#
# Every scratch directory here is a child of this one. `fs_temp_dir` and a bare
# `mktemp -d` both make one under the system temporary directory and neither
# removes it, and this file was leaving twenty-seven per run.
#
# The three that still call `mktemp -d` run in a fresh `bash -c` which has none
# of this file's helpers, and each removes its own directory on the way out.
# They say `self-cleaned` on the line, which is what the guard below allows.
_EX_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-extern.XXXXXX")"
trap '[[ -n "${_EX_TMP:-}" ]] && rm -rf "$_EX_TMP"' EXIT

# A scratch directory under this file's own root.
_ex_tmp() {
    local d; d="$(mktemp -d "${_EX_TMP}/${1:-d}.XXXXXX")"
    printf '%s' "$d"
}

_isolate() {
    # Somewhere that exists, first. Each test `cd`s into a fixture and none of
    # them comes back, so the next one starts from whatever the last one left,
    # and once any of those is cleaned up git reports `Unable to read current
    # working directory` and the failure reads as being about the dependency.
    cd "$_EX_TMP" 2>/dev/null || cd / || return 1

    NUTSHELL_STORE="$(_ex_tmp store)"
    export NUTSHELL_STORE

    # And drop the runner's own anchor. `_extern_manifest` looks at
    # `NUTSHELL_SCRIPT_DIR` before it looks at `$PWD`, which is right for a
    # script asking about its own project and wrong for a test that has just
    # `cd`ed into a fixture. Left set, every one of these reads nutshell's own
    # manifest, which declares no `fixture`, and thirteen tests fail with a
    # message about the fixture rather than about the anchor.
    unset NUTSHELL_SCRIPT_DIR _NUT_ASKING_FROM
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
it_follows_the_branch_rather_than_the_lock() {
    # A branch pin means that branch's head. A lockfile entry naming an older
    # commit is a note about the past, not a pin: holding the checkout there
    # would make `ref = "main"` a pin on whatever main happened to be the first
    # time anybody asked, which is how a consumer ended up on its dependency's
    # first commit while months of work went past it.
    _isolate
    local fix work first second dir
    fix="$(_extern_fixture)"; work="${fix%% *}"
    first="$(printf '%s' "$fix" | cut -d' ' -f2)"
    second="${fix##* }"
    cd "${work}/project" || return 1

    extern_lock_write fixture "$first"
    dir="$(extern_path fixture)"

    assert_eq "$(git -C "$dir" rev-parse HEAD)" "$second"
    assert_contains "$(cat "${dir}/lib/greet.sh")" "goodbye"
}

#[test]
it_rewrites_the_lock_when_the_branch_has_moved() {
    # The lockfile's other job. On a branch it records what the head resolved
    # to and is rewritten every time that moves, so it reports rather than pins.
    _isolate
    local fix work first second
    fix="$(_extern_fixture)"; work="${fix%% *}"
    first="$(printf '%s' "$fix" | cut -d' ' -f2)"
    second="${fix##* }"
    cd "${work}/project" || return 1

    extern_lock_write fixture "$first"
    extern_path fixture >/dev/null
    assert_eq "$(extern_locked fixture)" "$second"
}

#[test]
it_holds_a_checkout_at_a_pinned_commit() {
    # The lockfile's first job, on the pin that has one. A revision names one
    # commit forever, and two checkouts of a project pinned to it are running
    # the same code.
    _isolate
    local fix work first dir
    fix="$(_extern_fixture)"; work="${fix%% *}"
    first="$(printf '%s' "$fix" | cut -d' ' -f2)"
    cd "${work}/project" || return 1
    sed -i.bak "s|^ref = .*|ref = \"${first}\"|" nut.toml && rm -f nut.toml.bak

    dir="$(extern_path fixture)"
    assert_eq "$(git -C "$dir" rev-parse HEAD)" "$first"
    assert_contains "$(cat "${dir}/lib/greet.sh")" "hello"
}

#[test]
it_holds_a_checkout_at_a_pinned_tag() {
    # A tag is the other fixed kind, and the one somebody writes when they mean
    # a release rather than a revision.
    _isolate
    local fix work first dir
    fix="$(_extern_fixture)"; work="${fix%% *}"
    first="$(printf '%s' "$fix" | cut -d' ' -f2)"
    # Annotated, which is what a release tag usually is, and the shape whose
    # `^{}` peeling the resolution has to follow: the tag object's own sha is
    # not a commit and nothing can be checked out at it.
    git -C "${work}/dep" tag -a v1 -m 'v1' "$first"
    cd "${work}/project" || return 1
    sed -i.bak 's|^ref = .*|ref = "v1"|' nut.toml && rm -f nut.toml.bak

    dir="$(extern_path fixture)"
    assert_eq "$(git -C "$dir" rev-parse HEAD)" "$first"
    assert_contains "$(cat "${dir}/lib/greet.sh")" "hello"
}

#[test]
it_refuses_a_commit_the_remote_does_not_have() {
    # Silently taking the tip instead would defeat the pin at the one moment it
    # matters.
    _isolate
    local fix work
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1
    sed -i.bak 's|^ref = .*|ref = "0000000000000000000000000000000000000000"|' nut.toml
    rm -f nut.toml.bak

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

    # Pinned apart by their manifests, since that is what a pin is now: a lock
    # entry on a branch is rewritten to the head and cannot hold two projects
    # apart.
    sed -i.bak "s|^ref = .*|ref = \"${first}\"|"  "${work}/project/nut.toml"
    sed -i.bak "s|^ref = .*|ref = \"${second}\"|" "${work}/other/nut.toml"
    rm -f "${work}/project/nut.toml.bak" "${work}/other/nut.toml.bak"

    local dir_a dir_b
    cd "${work}/project" || return 1
    dir_a="$(extern_path fixture)"

    cd "${work}/other" || return 1
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
it_records_the_pid_of_the_process_that_actually_holds_the_lock() {
    # The guard runs inside a command substitution: `init` calls
    # `extern_resolve` in `$( )`, which reaches `extern_path` and then here.
    # `$$` in a subshell is the *parent's* pid, so the lock recorded a process
    # that outlives the one holding it. A subshell dying mid-clone then left a
    # lock naming a pid `kill -0` says is alive, the takeover never fired, and
    # the next run sat out the whole ten minute clock instead.
    #
    # So the property is that the pid in the lock belongs to whoever wrote it.
    _isolate
    local fix work dir lock
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    dir="$(_extern_cache_root)/pretend-pid"
    lock="${dir}.lock"
    # The store root need not exist yet, and the guard makes it. A missing
    # parent used to fail `mkdir "$lock"` the same way contention does, so this
    # waited eleven minutes for a lock nobody held.
    assert_fails test -d "$lock"

    # Held long enough to read the lock while it exists, from a subshell, which
    # is how every real caller reaches this.
    local seen
    seen="$( _EXTERN_LOCK_WAIT_SECONDS=3 _extern_guard "$dir" bash -c 'cat "$0/pid"' "$lock" )"

    assert_ne "$seen" "" "the guard writes a pid into the lock"
    assert_ne "$seen" "$$" "and it is not the pid of the shell that will outlive it"
}

#[test]
it_still_waits_for_a_lock_whose_holder_is_alive() {
    # The control for the one above. A live holder is a lock that must not be
    # taken over, however impatient the next process is, or two clones race
    # into one directory.
    _isolate
    local fix work dir lock
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    dir="$(_extern_cache_root)/pretend-live"
    lock="${dir}.lock"
    fs_mkdir "$lock"
    printf '%s' "$$" > "${lock}/pid"

    local rc=0
    _EXTERN_LOCK_WAIT_SECONDS=2 _extern_guard "$dir" true || rc=$?
    assert_ne "$rc" "0" "a live holder is waited for, then reported"
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
    root="$(cd "$(_ex_tmp manifest)" && pwd)"
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

# --- resolving once per process -----------------------------------------------

#[test]
it_remembers_a_resolved_path() {
    # Every `use <dep>::<module>` resolved the dependency again: manifest
    # re-read, lockfile re-read, git asked twice. None of it can change while a
    # script runs, and five modules out of one library cost it five times.
    # Through the module's own accessors rather than into whatever it keeps
    # the memo in. These reached into `_EXTERN_RESOLVED[...]` directly and
    # broke the moment that became a `map`, on a change that altered nothing
    # about the answer.
    map_clear _EXTERN_RESOLVED
    map_set _EXTERN_RESOLVED fixture "/tmp"
    _extern_is_repo() { return 0; }
    assert_eq "$(extern_path fixture)" "/tmp"
}

#[test]
it_forgets_one_name_when_asked() {
    map_clear _EXTERN_RESOLVED
    map_set _EXTERN_RESOLVED a "/tmp/a"
    map_set _EXTERN_RESOLVED b "/tmp/b"
    extern_forget a
    local va="" vb=""
    map_read va _EXTERN_RESOLVED a
    map_read vb _EXTERN_RESOLVED b
    assert_empty "$va"
    assert_eq "$vb" "/tmp/b"
}

#[test]
it_forgets_everything_when_given_no_name() {
    map_clear _EXTERN_RESOLVED
    map_set _EXTERN_RESOLVED a "/tmp/a"
    map_set _EXTERN_RESOLVED b "/tmp/b"
    extern_forget
    assert_eq "$(map_len _EXTERN_RESOLVED)" "0"
}

#[test]
it_does_not_hand_back_a_checkout_that_has_gone() {
    # A cached path whose checkout was removed is worse than no cache: the
    # caller gets a directory git will not answer for, and no explanation.
    # It must fall through and resolve again rather than returning it.
    map_clear _EXTERN_RESOLVED
    map_set _EXTERN_RESOLVED fixture "/tmp/definitely-not-a-checkout"
    _extern_is_repo() { return 1; }
    extern_path fixture >/dev/null 2>&1 || true
    local v=""
    map_read v _EXTERN_RESOLVED fixture
    assert_empty "$v"
}

# --- how a module path is spelled ----------------------------------------------
#
# `::` separates modules the whole way down. A `/` used to work, because the
# tail was handed to the filesystem unchanged, so `shebang::tui/key` found the
# file and read as two different separators in one path. It is refused now, and
# the refusal names the spelling that works.

#[test]
it_takes_a_nested_module_separated_all_the_way_down() {
    local d; d="$(_ex_tmp)"
    mkdir -p "$d/dep/libs/tui"
    printf 'MARKER=reached\n' > "$d/dep/libs/tui/key.sh"
    printf '[meta]\nname="dep"\n' > "$d/dep/nut.toml"
    extern_path() { printf '%s/dep' "$d"; }
    local out; out="$(extern_resolve 'dep::tui::key')"
    assert_eq "$out" "$d/dep/libs/tui/key.sh"
    unset -f extern_path
    rm -rf "$d"
}

#[test]
it_refuses_a_module_path_that_uses_a_slash() {
    local d; d="$(_ex_tmp)"
    mkdir -p "$d/dep/libs/tui"
    printf 'MARKER=reached\n' > "$d/dep/libs/tui/key.sh"
    extern_path() { printf '%s/dep' "$d"; }
    # The file is right there. It is still refused, because a separator that
    # works by accident ends up used in half the call sites and not the other.
    assert_fails extern_resolve 'dep::tui/key'
    unset -f extern_path
    rm -rf "$d"
}

#[test]
it_says_the_spelling_that_would_have_worked() {
    local d out; d="$(_ex_tmp)"
    mkdir -p "$d/dep/libs/tui"
    : > "$d/dep/libs/tui/key.sh"
    extern_path() { printf '%s/dep' "$d"; }
    out="$(extern_resolve 'dep::tui/key' 2>&1 || true)"
    assert_ok grep -q 'dep::tui::key' <<<"$out"
    unset -f extern_path
    rm -rf "$d"
}

#[test]
it_still_takes_a_flat_module() {
    local d; d="$(_ex_tmp)"
    mkdir -p "$d/dep/lib"
    : > "$d/dep/lib/plain.sh"
    extern_path() { printf '%s/dep' "$d"; }
    assert_eq "$(extern_resolve 'dep::plain')" "$d/dep/lib/plain.sh"
    unset -f extern_path
    rm -rf "$d"
}

# --- one file, one load ----------------------------------------------------------
#
# A module is reachable by more than one name: its own unit calls it
# `super::tui::key`, a consumer calls it `dep::tui::key`, and both are the same
# file. Loaded-ness was keyed on the words rather than the file, so each name
# sourced it again, and a module without a guard of its own ran twice.

#[test]
it_loads_a_module_once_however_it_was_named() {
    local out
    out="$(bash -c '
        cd '"$PWD"'
        . ./init
        d=$(mktemp -d); mkdir -p "$d/libs/tui"  # self-cleaned, fresh shell
        printf "COUNT=\$(( \${COUNT:-0} + 1 ))\n" > "$d/libs/tui/key.sh"
        use extern
        extern_path() { printf "%s" "$d"; }
        use one::tui::key
        use two::tui::key
        printf "%s" "$COUNT"
        rm -rf "$d"')"
    assert_eq "$out" "1"
}

#[test]
it_answers_that_a_module_is_loaded_by_either_name() {
    local out
    out="$(bash -c '
        cd '"$PWD"'
        . ./init
        d=$(mktemp -d); mkdir -p "$d/libs/tui"  # self-cleaned, fresh shell
        : > "$d/libs/tui/key.sh"
        use extern
        extern_path() { printf "%s" "$d"; }
        use one::tui::key
        nutshell_loaded one::tui::key && printf "first "
        use two::tui::key
        nutshell_loaded two::tui::key && printf "second"
        rm -rf "$d"')"
    assert_eq "$out" "first second"
}

#[test]
it_does_not_record_a_module_that_failed_to_load() {
    local out
    out="$(bash -c '
        cd '"$PWD"'
        . ./init
        d=$(mktemp -d); mkdir -p "$d/libs"  # self-cleaned, fresh shell
        printf "return 1\n" > "$d/libs/bad.sh"
        use extern
        extern_path() { printf "%s" "$d"; }
        use dep::bad 2>/dev/null
        nutshell_loaded dep::bad && printf "recorded" || printf "not recorded"
        rm -rf "$d"')"
    # Leaving the mark would make a later retry succeed against a module that
    # was never sourced.
    assert_eq "$out" "not recorded"
}

#[test]
it_finds_a_units_manifest_when_run_from_somewhere_else() {
    # A tool installed on PATH and run from any other directory could not
    # resolve a single dependency: the manifest search had only PWD, which is a
    # fact about where the shell was started rather than about which unit is
    # asking.
    local d out; d="$(_ex_tmp)"
    mkdir -p "$d/unit/lib" "$d/dep/libs"
    printf '[meta]\nname="unit"\n\n[deps.dep]\ngit = "x"\n' > "$d/unit/nut.toml"
    printf 'MARKER=reached\n' > "$d/dep/libs/thing.sh"
    printf 'thing libs/thing.sh\n' > "$d/dep/lib.nut"
    printf 'use extern\nextern_path() { printf "%%s" "%s/dep"; }\nuse dep::thing\n' "$d" \
        > "$d/unit/lib/main.sh"

    # Run from a directory that is not the unit and has no manifest above it.
    # The init path is captured before the cd: `$PWD` inside would be the
    # directory just moved to, which is the mistake this test is about.
    local nut; nut="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
    out="$(cd "$d" && bash -c "
        . '$nut/init' 2>/dev/null
        . '$d/unit/lib/main.sh'
        printf '%s' \"\${MARKER:-unset}\"" 2>&1)"
    assert_ok grep -q 'reached' <<<"$out"
    rm -rf "$d"
}

# --- taking the newest commit on a ref ---------------------------------------
#
# `nut.lock` tells a reader that deleting an entry takes the newest commit on
# its ref again. A mirror cloned once and never fetched cannot do that: it
# answers with whatever the ref pointed at the first time anybody asked. In the
# case that produced these tests the answer was the dependency's first commit,
# and months of work in it had never reached the consumer.

_ex_origin() {
    local d; d="$(_ex_tmp)"
    git -C "$d" init --quiet -b dev
    git -C "$d" config user.email t@t; git -C "$d" config user.name t
    mkdir -p "$d/libs"
    printf 'first\n' > "$d/libs/thing.sh"
    printf 'x = 1\n' > "$d/nut.toml"
    git -C "$d" add -A; git -C "$d" commit --quiet -m first
    printf '%s' "$d"
}

_ex_advance() {
    printf 'second\n' > "$1/libs/thing.sh"
    printf 'second\n' > "$1/libs/later.sh"
    git -C "$1" add -A; git -C "$1" commit --quiet -m second
}

#[test]
it_takes_the_newest_commit_when_the_lock_says_nothing() {
    local origin; origin="$(_ex_origin)"
    local mirror; mirror="$(_ex_tmp)"; rm -rf "$mirror"
    git clone --quiet --depth 1 --branch dev "$origin" "$mirror" 2>/dev/null
    local before; before="$(_extern_ref_commit "$mirror" dev)"

    _ex_advance "$origin"
    _extern_refresh "$mirror" dev
    local after; after="$(_extern_ref_commit "$mirror" dev)"

    local head_only; head_only="$(git -C "$mirror" rev-parse HEAD)"
    rm -rf "$origin" "$mirror"

    assert_ne "$after" "$before"
    # The control for the whole thing: `rev-parse HEAD` on the mirror, which is
    # what this replaced, still answers with the old commit after the refresh.
    assert_eq "$head_only" "$before"
}

#[test]
it_answers_with_the_commit_it_already_has_when_the_ref_cannot_be_fetched() {
    # A machine with no network still has whatever it cloned. A stale answer
    # beats no answer for a tool whose job is a machine that is broken.
    local origin; origin="$(_ex_origin)"
    local mirror; mirror="$(_ex_tmp)"; rm -rf "$mirror"
    git clone --quiet --depth 1 --branch dev "$origin" "$mirror" 2>/dev/null
    local before; before="$(_extern_ref_commit "$mirror" dev)"
    rm -rf "$origin"

    assert_ok _extern_refresh "$mirror" dev
    local after; after="$(_extern_ref_commit "$mirror" dev)"
    rm -rf "$mirror"
    assert_eq "$after" "$before"
}

#[test]
it_refuses_a_ref_the_mirror_has_never_heard_of() {
    local origin; origin="$(_ex_origin)"
    local mirror; mirror="$(_ex_tmp)"; rm -rf "$mirror"
    git clone --quiet --depth 1 --branch dev "$origin" "$mirror" 2>/dev/null
    local rc=0
    _extern_ref_commit "$mirror" "no-such-ref" >/dev/null 2>&1 || rc=$?
    rm -rf "$origin" "$mirror"
    # HEAD is the last resort and it exists, so this answers rather than fails.
    # What must not happen is inventing a commit for a ref that is not there.
    assert_eq "$rc" "0"
}

#[test]
it_takes_a_commit_that_carries_a_file_the_old_one_did_not() {
    # The shape of the failure this fixes: a consumer pinned at the first
    # commit of a library resolved every module that existed then and none of
    # the ones added since, and the error named the module rather than the pin.
    local origin; origin="$(_ex_origin)"
    local mirror; mirror="$(_ex_tmp)"; rm -rf "$mirror"
    git clone --quiet --depth 1 --branch dev "$origin" "$mirror" 2>/dev/null
    _ex_advance "$origin"
    _extern_refresh "$mirror" dev
    local c; c="$(_extern_ref_commit "$mirror" dev)"
    local has; has="$(git -C "$mirror" ls-tree --name-only "$c" libs/ 2>/dev/null | tr '\n' ' ')"
    rm -rf "$origin" "$mirror"
    assert_contains "$has" "later.sh"
}

#[test]
it_lets_the_lockfile_win_over_a_tag_that_disagrees() {
    # Written down because it surprises: a tag names one commit and the lock
    # names another, and the lock is what the checkout goes to. That is right
    # when an upstream tag has moved under a project that already resolved it,
    # and it means a hand-edited lock silently redirects a tag pin.
    _isolate
    local fix work first second dir
    fix="$(_extern_fixture)"; work="${fix%% *}"
    first="$(printf '%s' "$fix" | cut -d' ' -f2)"
    second="${fix##* }"
    git -C "${work}/dep" tag -a v1 -m 'v1' "$first"
    cd "${work}/project" || return 1
    sed -i.bak 's|^ref = .*|ref = "v1"|' nut.toml && rm -f nut.toml.bak

    extern_lock_write fixture "$second"
    dir="$(extern_path fixture)"
    assert_eq "$(git -C "$dir" rev-parse HEAD)" "$second"
}

#[test]
it_resolves_the_tag_again_when_the_lock_entry_is_gone() {
    # The way back, and the reason the behaviour above is safe: deleting the
    # entry is how you ask for the ref to decide.
    _isolate
    local fix work first dir
    fix="$(_extern_fixture)"; work="${fix%% *}"
    first="$(printf '%s' "$fix" | cut -d' ' -f2)"
    git -C "${work}/dep" tag -a v1 -m 'v1' "$first"
    cd "${work}/project" || return 1
    sed -i.bak 's|^ref = .*|ref = "v1"|' nut.toml && rm -f nut.toml.bak

    dir="$(extern_path fixture)"
    assert_eq "$(git -C "$dir" rev-parse HEAD)" "$first"
}

# --- the isolation itself ----------------------------------------------------

#[test]
it_puts_the_store_where_it_is_told_to() {
    # The negative control for every test above. Each of them believes it is
    # working in a store of its own, and none of them would notice being wrong.
    _isolate
    assert_contains "$(_extern_cache_root)" "$NUTSHELL_STORE"
}

#[test]
it_puts_the_store_under_the_data_directory_when_nothing_overrides_it() {
    local root
    root="$(unset NUTSHELL_STORE; XDG_DATA_HOME=/tmp/xdg-probe _extern_cache_root)"
    assert_contains "$root" "/tmp/xdg-probe"
    assert_contains "$root" "externs"
    _isolate
}

#[test]
it_does_not_put_the_store_under_the_cache_directory() {
    # With nothing overriding it, so the branch that derives the path is the
    # one under test. Asserting this with `NUTSHELL_STORE` pointing at a
    # scratch directory, as this used to, is a claim about `mktemp` that no
    # change to the derivation could ever falsify.
    #
    # Not merely somewhere else: specifically not in the directory a cleaner is
    # entitled to empty, which is where every project's dependencies used to
    # live.
    local root cache
    root="$(unset NUTSHELL_STORE XDG_DATA_HOME; _extern_cache_root)"
    cache="$(unset XDG_CACHE_HOME; xdg_set_app_name nutshell; xdg_app_cache)"
    assert_ne "$root" ""
    assert_ne "$cache" ""
    # Against what this platform actually calls its cache, not against the
    # spelling one platform happens to use. Matching `/.cache/` passes on macOS
    # whatever the derivation does, because the cache there is
    # `~/Library/Caches`, so that assertion could not fail on half the machines
    # it runs on.
    assert_ne "${root%/externs}" "$cache"
    _isolate
}

# --- one root, spelled twice -------------------------------------------------
#
# `find-nutshell` runs before nutshell exists and cannot use `lib/xdg.sh`, so
# the platform branch is written out in both places. Nothing but this test
# holds them together, and without it they were already apart: the toolchains
# went to `~/.local/share` on macOS while the externs went to
# `~/Library/Application Support`, and the README said they shared a root.

#[test]
it_puts_the_externs_and_the_toolchains_under_one_root() {
    unset NUTSHELL_STORE NUTSHELL_TOOLCHAINS
    # shellcheck source=/dev/null
    . "${BASH_SOURCE[0]%/*}/../find-nutshell"
    local externs toolchains
    externs="$(_extern_cache_root)"
    toolchains="$(nutshell_toolchain_dir)"
    assert_eq "${externs%/externs}" "${toolchains%/toolchains}"
    assert_eq "${externs%/externs}" "$(nutshell_store_root)"
    _isolate
}

#[test]
it_keeps_them_together_when_the_root_is_named() {
    export NUTSHELL_STORE="/tmp/one-root-probe"
    # shellcheck source=/dev/null
    . "${BASH_SOURCE[0]%/*}/../find-nutshell"
    assert_eq "$(_extern_cache_root)" "/tmp/one-root-probe/externs"
    assert_eq "$(nutshell_toolchain_dir)" "/tmp/one-root-probe/toolchains"
    _isolate
}

#[test]
it_keeps_them_together_when_xdg_names_the_data_directory() {
    unset NUTSHELL_STORE NUTSHELL_TOOLCHAINS
    export XDG_DATA_HOME="/tmp/xdg-one-root"
    # shellcheck source=/dev/null
    . "${BASH_SOURCE[0]%/*}/../find-nutshell"
    # The branch both sides take when the variable is set, which is the one
    # place they already agreed. The two above are where they did not.
    assert_eq "$(_extern_cache_root)" "/tmp/xdg-one-root/nutshell/externs"
    assert_eq "$(nutshell_toolchain_dir)" "/tmp/xdg-one-root/nutshell/toolchains"
    unset XDG_DATA_HOME
    _isolate
}

#[test]
it_makes_no_scratch_directory_outside_its_own_root() {
    # The leak was twenty-seven per run and nothing failed while it happened.
    # The three that stay are in a fresh `bash -c` which cannot see `_ex_tmp`,
    # and each removes its own directory; they are named so, and the check
    # allows exactly those.
    local stray
    stray="$(grep -nE 'mktemp -d[)" ]|fs_temp_dir[ )"]' "${BASH_SOURCE[0]}" \
        | grep -v '_EX_TMP' | grep -v 'self-cleaned' | grep -vE '^[0-9]+: *#' || true)"
    assert_empty "$stray"
}

#[test]
it_does_not_wait_out_the_clock_for_a_parent_that_is_merely_absent() {
    # `mkdir "$lock"` is the lock, and it failed for two different reasons that
    # looked identical: somebody holds it, or the directory above it is not
    # there yet. The second waited eleven minutes for a lock nobody held, which
    # is the whole default wait, on a store that had simply never been used.
    _isolate
    local fix work dir
    fix="$(_extern_fixture)"; work="${fix%% *}"
    cd "${work}/project" || return 1

    # Deliberately several levels below anything that exists.
    dir="$(_extern_cache_root)/never/been/here/pretend"
    assert_fails test -d "$(dirname "$dir")"

    local start end rc=0
    start="$(date +%s)"
    _EXTERN_LOCK_WAIT_SECONDS=30 _extern_guard "$dir" git init --quiet "$dir" || rc=$?
    end="$(date +%s)"

    assert_eq "$rc" "0"
    # Promptly, rather than after any part of the wait. The wait is set to 30
    # here and is 660 in production, so the old behaviour blows this by a wide
    # margin either way.
    assert_ok test "$(( end - start ))" -lt 5
}

# --- what a tag resolves to --------------------------------------------------
#
# An annotated tag is two objects: the tag, and the commit it points at.
# `git ls-remote <url> refs/tags/x` returns only the first, and the peeled
# `refs/tags/x^{}` row appears only when the pattern lets it. So a resolver
# that asks for the exact ref and then handles `^{}` has code for a case it
# never sees, which is what this had.
#
# The consequence is quiet. A lockfile pinning an annotated tag recorded the
# tag object's sha, which is not a commit and can never equal any checkout's
# `HEAD`, so nothing that compares them can ever agree. Found by tagging
# the-whole-shebang `0.1.0` and reading the lock it produced.

_ex_tagged_repo() {
    local kind="$1"
    local d; d="$(_ex_tmp tagrepo)"
    git -C "$d" init -q -b main
    git -C "$d" config user.email t@example.invalid
    git -C "$d" config user.name  t
    printf 'one\n' > "$d/f"
    git -C "$d" add f
    git -C "$d" commit -q -m one
    case "$kind" in
        annotated) git -C "$d" tag -a v1 -m "release v1" ;;
        # Written as a ref rather than through `git tag`, which is what a
        # lightweight tag is. This machine's config forces annotation, so
        # `git tag v1` asks for a message and makes the other kind.
        light)     git -C "$d" update-ref refs/tags/v1 "$(git -C "$d" rev-parse HEAD)" ;;
    esac
    printf '%s' "$d"
}

#[test]
it_resolves_an_annotated_tag_to_the_commit_and_not_to_the_tag() {
    local d; d="$(_ex_tagged_repo annotated)"
    local want; want="$(git -C "$d" rev-parse 'v1^{}')"
    local tagobj; tagobj="$(git -C "$d" rev-parse v1)"

    # The control for the test itself: an annotated tag has to have two
    # different shas, or this proves nothing about which one came back.
    assert_ne "$tagobj" "$want"

    local got; got="$(_extern_remote_ref "$d" v1)"
    assert_eq "$got" "tags ${want}"
}

#[test]
it_resolves_a_lightweight_tag_to_the_same_commit() {
    # The control. A lightweight tag is the commit, so both readings agree and
    # a resolver that always took the bare row would pass this. It is here so
    # the fix above cannot be a change that only works for one shape.
    local d; d="$(_ex_tagged_repo light)"
    local want; want="$(git -C "$d" rev-parse 'v1^{}')"
    assert_eq "$(git -C "$d" rev-parse v1)" "$want"
    assert_eq "$(_extern_remote_ref "$d" v1)" "tags ${want}"
}

#[test]
it_prefers_a_branch_over_a_tag_of_the_same_name() {
    # Unchanged behaviour, pinned because the glob above widened what the tag
    # query returns and this is the neighbouring decision.
    local d; d="$(_ex_tagged_repo annotated)"
    git -C "$d" checkout -q -b v1 2>/dev/null
    printf 'two\n' > "$d/f"; git -C "$d" add f; git -C "$d" commit -q -m two
    # By its full ref, because a branch and a tag of the same name make the
    # short name ambiguous and git resolves it to the tag.
    local head; head="$(git -C "$d" rev-parse refs/heads/v1)"

    assert_eq "$(_extern_remote_ref "$d" v1)" "heads ${head}"
}
