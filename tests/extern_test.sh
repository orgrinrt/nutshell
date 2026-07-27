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
