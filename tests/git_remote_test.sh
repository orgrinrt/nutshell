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
it_answers_the_remotes_head_when_asked_and_it_has_neither_dev_nor_main() {
    local r; r="$(_fixture release)"
    local got; got="$( cd "$r/clone" && git_trunk --remote --or-head )"
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
    assert_exits 1 git_is_clean "$r/clone"
    rm -rf "$r"
}

#[test]
it_calls_an_unstaged_change_unclean() {
    local r; r="$(_fixture main)"
    echo changed > "$r/clone/a.txt"
    assert_exits 1 git_is_clean "$r/clone"
    rm -rf "$r"
}

#[test]
it_calls_an_untracked_file_unclean() {
    local r; r="$(_fixture main)"
    echo new > "$r/clone/new.txt"
    assert_exits 1 git_is_clean "$r/clone"
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
    assert_exits 2 git_is_clean "$d"
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
    assert_exits 2 git_unpushed "$d"
    rm -rf "$d"
}

#[test]
it_fails_for_a_remote_with_neither_dev_nor_main_unless_asked_for_its_head() {
    local r; r="$(_fixture release)"
    assert_exits 1 git_trunk -C "$r/clone" --remote
    assert_exits 1 git_trunk -C "$r/clone" --remote --live
    assert_eq "$(git_trunk -C "$r/clone" --remote --or-head)" "release"
    assert_eq "$(git_trunk -C "$r/clone" --remote --live --or-head)" "release"
    rm -rf "$r"
}

#[test]
it_prefers_the_remotes_dev_over_its_head_even_when_head_is_asked_for() {
    local r; r="$(_fixture release dev main)"
    assert_eq "$(git_trunk -C "$r/clone" --remote --or-head)" "dev"
    rm -rf "$r"
}

#[test]
it_takes_a_preference_list_for_the_remote_in_the_callers_order() {
    local r; r="$(_fixture main dev release)"
    assert_eq "$(git_trunk -C "$r/clone" --remote release dev)" "release"
    assert_eq "$(git_trunk -C "$r/clone" --remote nothing main)" "main"
    assert_eq "$(git_trunk -C "$r/clone" --remote --live release main)" "release"
    assert_exits 1 git_trunk -C "$r/clone" --remote nothing
    assert_eq "$(git_trunk -C "$r/clone" --remote --or-head nothing)" "main" "the head of the remote, which was seeded on main"
    rm -rf "$r"
}

#[test]
it_fails_for_an_unreachable_live_remote() {
    local r; r="$(_fixture main dev)"
    git -C "$r/clone" remote set-url origin "http://127.0.0.1:1/none.git"
    assert_exits 1 git_trunk -C "$r/clone" --remote --live
    assert_eq "$(git_trunk -C "$r/clone" --remote)" "dev" "the tracking refs still answer without the network"
    rm -rf "$r"
}

#[test]
it_names_a_remote_whose_name_holds_regex_and_sed_characters() {
    local r; r="$(_fixture main dev)"
    git -C "$r/clone" remote add 'up|s.ream' "$r/remote.git"
    git -C "$r/clone" fetch -q 'up|s.ream'
    git -C "$r/clone" remote set-head 'up|s.ream' main
    assert_eq "$(git_trunk -C "$r/clone" --remote='up|s.ream')" "dev"
    assert_eq "$(git_trunk -C "$r/clone" --remote='up|s.ream' --or-head nothing)" "main"
    rm -rf "$r"
}

#[test]
it_lists_a_commit_on_a_detached_head() {
    local r; r="$(_fixture main)"
    git -C "$r/clone" checkout -q --detach
    _gc -C "$r/clone" commit -q --allow-empty -m "feat: on no branch"
    local sha; sha="$(git -C "$r/clone" rev-parse HEAD)"
    assert_contains "$(git_unpushed "$r/clone")" "$sha"
    rm -rf "$r"
}

#[test]
it_lists_a_commit_on_the_detached_head_of_a_linked_worktree() {
    local r; r="$(_fixture main)"
    git -C "$r/clone" worktree add -q --detach "$r/wt"
    _gc -C "$r/wt" commit -q --allow-empty -m "feat: in the worktree"
    local sha; sha="$(git -C "$r/wt" rev-parse HEAD)"
    assert_contains "$(git_unpushed "$r/clone")" "$sha" "asked from the main checkout"
    assert_contains "$(git_unpushed "$r/wt")" "$sha" "asked from the worktree"
    rm -rf "$r"
}

#[test]
it_lists_a_stash_as_unpushed_and_not_clean() {
    local r; r="$(_fixture main)"
    echo changed > "$r/clone/a.txt"
    _gc -C "$r/clone" stash -q
    assert_eq "$(git -C "$r/clone" status --porcelain)" "" "the worktree itself is clean after the stash"
    assert_exits 1 git_is_clean "$r/clone"
    assert_contains "$(git_unpushed "$r/clone")" "WIP on main"
    rm -rf "$r"
}

#[test]
it_calls_a_stash_of_untracked_files_unclean() {
    local r; r="$(_fixture main)"
    echo new > "$r/clone/new.txt"
    _gc -C "$r/clone" stash -q -u
    assert_exits 1 git_is_clean "$r/clone"
    rm -rf "$r"
}

#[test]
it_is_clean_again_once_the_stash_is_dropped() {
    local r; r="$(_fixture main)"
    echo changed > "$r/clone/a.txt"
    _gc -C "$r/clone" stash -q
    git -C "$r/clone" stash drop -q
    assert_ok git_is_clean "$r/clone"
    assert_eq "$(git_unpushed "$r/clone")" ""
    rm -rf "$r"
}

#[test]
it_calls_a_bare_repository_clean_and_still_lists_its_unpushed_commits() {
    local r; r="$(_fixture main)"
    git clone -q --bare "$r/remote.git" "$r/bare.git" 2>/dev/null
    assert_ok git_is_clean "$r/bare.git"
    assert_contains "$(git_unpushed "$r/bare.git")" "feat: the first thing" "a bare clone keeps no remote-tracking refs, so no remote is known to carry its branches"
    git -C "$r/bare.git" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git -C "$r/bare.git" fetch -q origin
    assert_eq "$(git_unpushed "$r/bare.git")" "" "once a remote-tracking ref carries them"
    rm -rf "$r"
}
