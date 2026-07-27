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
    # The control: a resolver that always answered "dev" would pass the test
    # above and be wrong everywhere it matters.
    local d; d="$(make_repo)"
    local got; got="$( cd "$d" && git_trunk dev master main )"
    assert_ne "$got" "dev"
    rm -rf "$d"
}
