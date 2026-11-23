#!/usr/bin/env bash
# Tests for the questions a workspace asks of a clone beside its remote: which
# branch is the trunk over there, is the checkout detached, is there work that
# only this machine has. Every repository is built here, with a bare remote.

use git test

# The identity is pinned in the environment: a GIT_AUTHOR_* or GIT_COMMITTER_*
# the machine exports wins over the repository's config.
_gc() {
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
        git "$@"
}

# _fixture <remote branches...>
#
# Prints a scratch directory holding `remote.git` (bare, HEAD on its first
# named branch) and `clone`, cloned from it and checked out on that first
# branch alone. The remote's other branches are remote-tracking only.
_fixture() {
    local root; root="$(mktemp -d)"
    local first=$1
    git init -q --bare -b "$first" "$root/remote.git"
    git init -q -b "$first" "$root/seed"
    echo one > "$root/seed/a.txt"
    git -C "$root/seed" add -A
    _gc -C "$root/seed" commit -qm "feat: the first thing"
    git -C "$root/seed" remote add origin "$root/remote.git"
    local b
    for b in "$@"; do
        git -C "$root/seed" branch -q -f "$b" "$first" 2>/dev/null || true
        git -C "$root/seed" push -q origin "$b"
    done
    git clone -q "$root/remote.git" "$root/clone" 2>/dev/null
    git -C "$root/clone" config user.email t@t
    git -C "$root/clone" config user.name t
    printf '%s' "$root"
}

#[test]
it_answers_the_remotes_dev_when_local_has_only_main() {
    local r; r="$(_fixture main dev)"
    assert_eq "$(git -C "$r/clone" branch --format='%(refname:short)')" "main" "the local side has main alone"
    local got; got="$( cd "$r/clone" && git_trunk --remote )"
    assert_eq "$got" "dev"
    rm -rf "$r"
}

#[test]
it_keeps_the_local_answer_as_the_default() {
    local r; r="$(_fixture main dev)"
    local got; got="$( cd "$r/clone" && git_trunk dev main )"
    assert_eq "$got" "main" "dev is not a local branch of the clone"
    rm -rf "$r"
}

#[test]
it_answers_main_when_the_remote_has_no_dev() {
    local r; r="$(_fixture main)"
    local got; got="$( cd "$r/clone" && git_trunk --remote )"
    assert_eq "$got" "main"
    rm -rf "$r"
}

#[test]
it_answers_the_remotes_head_when_it_has_neither_dev_nor_main() {
    local r; r="$(_fixture release)"
    local got; got="$( cd "$r/clone" && git_trunk --remote )"
    assert_eq "$got" "release"
    rm -rf "$r"
}

#[test]
it_takes_the_directory_and_the_remote_by_name() {
    local r; r="$(_fixture main dev)"
    git -C "$r/clone" remote add other "$r/remote.git"
    git -C "$r/clone" fetch -q other
    assert_eq "$(git_trunk -C "$r/clone" --remote)" "dev"
    assert_eq "$(git_trunk -C "$r/clone" --remote=other)" "dev"
    assert_fails git_trunk -C "$r/clone" --remote=absent
    rm -rf "$r"
}

#[test]
it_refuses_a_remote_trunk_where_there_is_no_remote() {
    local d; d="$(mktemp -d)"
    git init -q -b main "$d"
    assert_fails git_trunk -C "$d" --remote
    rm -rf "$d"
}

#[test]
it_asks_the_remote_itself_when_live() {
    # The clone was made before the remote grew a dev, so its tracking refs do
    # not know of one.
    local r; r="$(_fixture main)"
    git -C "$r/seed" branch -q dev
    git -C "$r/seed" push -q origin dev
    assert_eq "$(git_trunk -C "$r/clone" --remote)" "main" "tracking refs only know main"
    assert_eq "$(git_trunk -C "$r/clone" --remote --live)" "dev"
    rm -rf "$r"
}

#[test]
it_names_a_branch_and_says_it_is_not_detached() {
    local r; r="$(_fixture main)"
    assert_eq "$(git_branch "$r/clone")" "main"
    assert_eq "$(git_branch --show-current "$r/clone")" "main"
    assert_eq "$(git_branch --kind "$r/clone")" "branch"
    rm -rf "$r"
}

#[test]
it_says_a_detached_checkout_is_detached() {
    local r; r="$(_fixture main)"
    git -C "$r/clone" checkout -q --detach
    assert_eq "$(git_branch "$r/clone")" "HEAD" "the long-standing answer for a detached head"
    assert_eq "$(git_branch --show-current "$r/clone")" "" "git's own empty answer"
    assert_eq "$(git_branch --kind "$r/clone")" "detached"
    rm -rf "$r"
}

#[test]
it_names_the_branch_of_a_repository_with_no_commit() {
    local d; d="$(mktemp -d)"
    git init -q -b fresh "$d"
    assert_eq "$(git_branch --show-current "$d")" "fresh"
    assert_eq "$(git_branch --kind "$d")" "branch"
    rm -rf "$d"
}

#[test]
it_answers_nothing_for_a_branch_where_there_is_no_repository() {
    local d; d="$(mktemp -d)"
    assert_fails git_branch --kind "$d"
    assert_fails git_branch --show-current "$d"
    rm -rf "$d"
}

#[test]
it_calls_a_checkout_with_nothing_changed_clean() {
    local r; r="$(_fixture main)"
    assert_ok git_is_clean "$r/clone"
    rm -rf "$r"
}

#[test]
it_calls_a_staged_change_unclean() {
    local r; r="$(_fixture main)"
    echo two > "$r/clone/b.txt"
    git -C "$r/clone" add b.txt
    assert_fails git_is_clean "$r/clone"
    rm -rf "$r"
}

#[test]
it_calls_an_unstaged_change_unclean() {
    local r; r="$(_fixture main)"
    echo changed > "$r/clone/a.txt"
    assert_fails git_is_clean "$r/clone"
    rm -rf "$r"
}

#[test]
it_calls_an_untracked_file_unclean() {
    local r; r="$(_fixture main)"
    echo new > "$r/clone/new.txt"
    assert_fails git_is_clean "$r/clone"
    rm -rf "$r"
}

#[test]
it_calls_an_ignored_file_alone_clean() {
    local r; r="$(_fixture main)"
    echo 'junk.log' > "$r/clone/.gitignore"
    git -C "$r/clone" add .gitignore
    _gc -C "$r/clone" commit -qm "chore: ignore logs"
    echo noise > "$r/clone/junk.log"
    assert_eq "$(git -C "$r/clone" status --porcelain --ignored)" "!! junk.log" "the file is on the floor, ignored"
    assert_ok git_is_clean "$r/clone"
    rm -rf "$r"
}

#[test]
it_refuses_to_call_a_non_repository_clean() {
    local d; d="$(mktemp -d)"
    assert_fails git_is_clean "$d"
    rm -rf "$d"
}

#[test]
it_lists_nothing_unpushed_for_a_clone_of_its_remote() {
    local r; r="$(_fixture main)"
    assert_eq "$(git_unpushed "$r/clone")" ""
    rm -rf "$r"
}

#[test]
it_lists_a_commit_on_a_branch_with_no_upstream() {
    local r; r="$(_fixture main)"
    git -C "$r/clone" checkout -q -b topic
    _gc -C "$r/clone" commit -q --allow-empty -m "feat: only here"
    local sha; sha="$(git -C "$r/clone" rev-parse HEAD)"
    git -C "$r/clone" checkout -q main
    assert_contains "$(git_unpushed "$r/clone")" "$sha"
    assert_contains "$(git_unpushed "$r/clone")" "feat: only here"
    rm -rf "$r"
}

#[test]
it_lists_nothing_once_the_branch_is_pushed() {
    local r; r="$(_fixture main)"
    git -C "$r/clone" checkout -q -b topic
    _gc -C "$r/clone" commit -q --allow-empty -m "feat: only here"
    git -C "$r/clone" push -q origin topic
    assert_eq "$(git_unpushed "$r/clone")" ""
    rm -rf "$r"
}

#[test]
it_lists_a_commit_ahead_of_its_upstream() {
    local r; r="$(_fixture main)"
    _gc -C "$r/clone" commit -q --allow-empty -m "feat: ahead"
    local sha; sha="$(git -C "$r/clone" rev-parse HEAD)"
    assert_contains "$(git_unpushed "$r/clone")" "$sha"
    git -C "$r/clone" push -q origin main
    assert_eq "$(git_unpushed "$r/clone")" ""
    rm -rf "$r"
}

#[test]
it_lists_every_commit_when_there_is_no_remote() {
    local d; d="$(mktemp -d)"
    git init -q -b main "$d"
    _gc -C "$d" commit -q --allow-empty -m "feat: lonely"
    assert_contains "$(git_unpushed "$d")" "feat: lonely"
    rm -rf "$d"
}

#[test]
it_refuses_to_list_unpushed_work_of_a_non_repository() {
    local d; d="$(mktemp -d)"
    assert_fails git_unpushed "$d"
    rm -rf "$d"
}
