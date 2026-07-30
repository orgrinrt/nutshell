#!/usr/bin/env bash
# Tests for repository interrogation, against a repository built here so the
# assertions do not depend on whatever state the real one is in.

use git test

make_repo() {
    local dir; dir="$(mktemp -d)"
    git -C "$dir" init -q
    git -C "$dir" config user.email t@t; git -C "$dir" config user.name t
    echo one > "$dir/a.txt"
    git -C "$dir" add -A; git -C "$dir" commit -qm "feat: the first thing"
    printf '%s' "$dir"
}

#[test]
it_recognises_a_repository() {
    local d; d="$(make_repo)"
    assert_ok git_is_repo "$d"
    rm -rf "$d"
}

#[test]
it_refuses_somewhere_that_is_not_one() {
    local d; d="$(mktemp -d)"
    assert_fails git_is_repo "$d"
    rm -rf "$d"
}

#[test]
it_picks_the_first_trunk_that_exists() {
    local d; d="$(make_repo)"
    ( cd "$d" && git checkout -qb dev )
    local got; got="$( cd "$d" && git_trunk dev main )"
    assert_eq "$got" "dev"
    rm -rf "$d"
}

#[test]
it_falls_back_when_the_preferred_trunk_is_absent() {
    # Names the branch it must find, not merely one it must not.
    #
    # This said `assert_ne "$got" "dev"` and called itself the control, and it
    # was not one: it passes against a resolver that returns nothing at all, or
    # a wrong branch, or anything except the string "dev".
    local d; d="$(make_repo)"
    local here; here="$( cd "$d" && git rev-parse --abbrev-ref HEAD )"
    local got; got="$( cd "$d" && git_trunk dev "$here" )"
    assert_eq "$got" "$here" "the first named branch that exists"
    rm -rf "$d"
}

#[test]
it_finds_no_trunk_when_none_of_them_exists() {
    local d; d="$(make_repo)"
    local got rc=0
    got="$( cd "$d" && git_trunk nope_a nope_b )" || rc=$?
    assert_ne "$rc" "0" "a resolver that finds nothing says so"
    assert_empty "$got"
    rm -rf "$d"
}

#[test]
it_finds_the_top_level_and_the_branch() {
    local d; d="$(make_repo)"
    assert_eq "$(git_root "$d")" "$(cd "$d" && pwd -P)"
    assert_ne "$(git_branch "$d")" ""
    rm -rf "$d"
}

#[test]
it_lists_what_a_branch_changed() {
    local d; d="$(make_repo)"
    (
        cd "$d" || exit 1
        base="$(git rev-parse --abbrev-ref HEAD)"
        git checkout -qb work
        echo two > b.txt
        mkdir -p docs && echo doc > docs/c.md
        git add -A && git commit -qm "feat: add two files"

        [[ "$(git_changed_files "$base" | sort | tr '\n' ' ')" == "b.txt docs/c.md " ]] || exit 2
        # A pathspec narrows it.
        [[ "$(git_changed_files "$base" docs)" == "docs/c.md" ]] || exit 3
        git_changed "$base" docs || exit 4
        git_changed "$base" nowhere && exit 5
        exit 0
    )
    assert_eq "$?" "0" "changed files, pathspec, and the yes-or-no form"
    rm -rf "$d"
}

#[test]
it_reads_only_the_added_side_of_a_diff() {
    # A check asking "did this branch introduce X" wants this. Asking it of the
    # whole diff finds X on the lines being deleted and reports the removal as
    # the offence.
    local d; d="$(make_repo)"
    (
        cd "$d" || exit 1
        base="$(git rev-parse --abbrev-ref HEAD)"
        git checkout -qb work
        printf 'kept\nintroduced\n' > a.txt
        git add -A && git commit -qm "feat: replace the line"

        added="$(git_added_lines "$base" a.txt)"
        [[ "$added" == *introduced* ]] || exit 2
        # `one` was removed, so it is on the minus side and must not appear.
        [[ "$added" != *one* ]] || exit 3
        exit 0
    )
    assert_eq "$?" "0" "added lines only"
    rm -rf "$d"
}

#[test]
it_reads_trailers_through_git_rather_than_by_grepping() {
    # git's own parser knows a trailer is a `Key: value` line in the final
    # block. A grep cannot tell that from a commit whose body discusses one,
    # and the difference decides whether a repository is considered
    # contaminated.
    local d; d="$(make_repo)"
    (
        cd "$d" || exit 1
        git commit -q --allow-empty -m "feat: a real trailer" -m "Co-Authored-By: Someone <s@example.com>"
        git commit -q --allow-empty -m "docs: discuss trailers" -m "The line Co-Authored-By: X goes in the last block, not here."

        out="$(git_trailers)"
        [[ "$out" == *"Co-Authored-By: Someone <s@example.com>"* ]] || exit 2
        # The second commit mentions one in prose. It has none.
        [[ "$(printf '%s\n' "$out" | grep -c 'Co-Authored-By')" -eq 1 ]] || exit 3
        exit 0
    )
    assert_eq "$?" "0" "a mention in prose is not a trailer"
    rm -rf "$d"
}

#[test]
it_lists_the_identities_that_wrote_a_repository() {
    local d; d="$(make_repo)"
    assert_contains "$(cd "$d" && git_identities)" "t <t@t>"
    rm -rf "$d"
}

#[test]
it_lists_the_subjects_a_branch_adds() {
    local d; d="$(make_repo)"
    (
        cd "$d" || exit 1
        base="$(git rev-parse --abbrev-ref HEAD)"
        git checkout -qb work
        git commit -q --allow-empty -m "feat: the second thing"

        out="$(git_subjects "$base")"
        [[ "$out" == *"feat: the second thing"* ]] || exit 2
        # The base's own commits are not this branch's.
        [[ "$out" != *"feat: the first thing"* ]] || exit 3
        exit 0
    )
    assert_eq "$?" "0" "only what this branch adds"
    rm -rf "$d"
}

#[test]
it_lists_tracked_files_and_ignores_the_rest() {
    local d; d="$(make_repo)"
    ( cd "$d" && echo x > untracked.txt )
    assert_contains "$(cd "$d" && git_tracked)" "a.txt"
    assert_fails grep -q untracked <<< "$(cd "$d" && git_tracked)"
    rm -rf "$d"
}

#[test]
it_measures_a_file_against_the_last_commit_not_the_clock() {
    # Staleness relative to the work, so a repository nobody touched for a year
    # does not read as having a stale README.
    local d; d="$(make_repo)"
    assert_eq "$(cd "$d" && git_file_age_days a.txt)" "0"
    rm -rf "$d"
}

#[test]
it_refuses_to_measure_a_file_that_is_not_there() {
    local d; d="$(make_repo)"
    assert_fails git_file_age_days "$d/nothing.txt"
    rm -rf "$d"
}
