#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/git.sh - Interrogating a repository
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0: shells out to git and nothing else.
#
# Reading, never writing. A module that could commit or push is a module
# somebody eventually calls by accident from a check script, and the blast
# radius of a mistake here is somebody's history.
#
# The functions are the questions scripts keep re-deriving: which branch is the
# trunk, what did this branch change, how stale is this file, does this commit
# carry that trailer. Each of them is three lines of git plumbing that everyone
# writes slightly differently, and the differences are invisible until two
# scripts disagree about the same repository.
#
# Usage:
#   use git
#
#   git_require_repo "$dir" || exit 2
#   base="$(git_trunk dev main)"
#   git_changed_files "$base" | while read -r f; do ...; done
# =============================================================================

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded: under a POSIX shell `nut_once` is not found, the `|| return
# 0` returns from the whole file, and the module then defines nothing while
# reporting success. That is worse than failing, because the caller has no way
# to tell.
[ -n "${_NUTSHELL_GIT_SH:-}" ] && return 0
_NUTSHELL_GIT_SH=1

use log

# -----------------------------------------------------------------------------
# Where are we
# -----------------------------------------------------------------------------

# git_is_repo [dir]
#[pub]
# Usage: git_is_repo [dir] -> returns 0 when it is one
git_is_repo() {
    local dir="${1:-.}"
    git -C "$dir" rev-parse --git-dir >/dev/null 2>&1
}

# git_require_repo [dir]
#
# Reports and fails rather than letting every later command fail separately
# with its own wording.
#[pub]
# Usage: git_require_repo [dir] -> returns 0, or reports and returns 1
git_require_repo() {
    local dir="${1:-.}"
    if ! git_is_repo "$dir"; then
        log_error "not a git repository: ${dir}"
        return 1
    fi
    return 0
}

# git_root [dir]
#[pub]
# Usage: git_root [dir] -> the worktree's top level
git_root() {
    git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null
}

# git_branch [dir]
#[pub]
# Usage: git_branch [dir] -> the checked-out branch
git_branch() {
    git -C "${1:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# git_trunk <preferred...>
#
# The first named branch that exists, so a caller states its policy once and
# still works in a repository that has not adopted it yet. `git_trunk dev main`
# is this workspace's rule written down: dev is the trunk, main is the fallback
# for a repository that has only just joined.
#[pub]
# Usage: git_trunk dev main -> the first of those that exists
git_trunk() {
    local candidate
    for candidate in "$@"; do
        if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# -----------------------------------------------------------------------------
# What changed
# -----------------------------------------------------------------------------

# git_changed_files <base> [pathspec...]
#
# Three dots: what this branch changed, not what has happened on the base since
# it was cut. The two-dot form makes every unrelated commit on the trunk look
# like part of the branch, which is the most common way a diff-driven check
# reports things nobody wrote.
#[pub]
# Usage: git_changed_files dev [pathspec...] -> one path per line
git_changed_files() {
    local base="$1"; shift
    git diff --name-only "${base}...HEAD" -- "$@" 2>/dev/null
}

# git_changed <base> <pathspec...>
#
# Whether anything under the pathspec changed. For the common branch rather
# than the list.
#[pub]
# Usage: git_changed dev docs -> returns 0 when anything under it changed
git_changed() {
    local base="$1"; shift
    [ -n "$(git_changed_files "$base" "$@")" ]
}

# git_added_lines <base> <pathspec>
#
# Only the added side of the diff. A check asking "did this branch introduce
# X" wants this; asking it of the whole diff finds X on the lines being deleted
# and reports the removal as the offence.
#[pub]
# Usage: git_added_lines dev src -> the added side of the diff
git_added_lines() {
    local base="$1" path="$2"
    git diff "${base}...HEAD" -- "$path" 2>/dev/null | grep '^+' | grep -v '^+++'
}

# -----------------------------------------------------------------------------
# Age
# -----------------------------------------------------------------------------

# git_file_age_days <path>
#
# How far behind the repository's last commit this file's last commit is.
# Staleness relative to the work rather than to the wall clock, so a repository
# nobody touched for a year does not read as having a stale README.
#[pub]
# Usage: git_file_age_days README.md -> commits behind HEAD, in days
git_file_age_days() {
    local path="$1"
    local file_at head_at
    file_at=$(git log -1 --format=%ct -- "$path" 2>/dev/null)
    head_at=$(git log -1 --format=%ct 2>/dev/null)
    { [ -z "$file_at" ] || [ -z "$head_at" ]; } && { printf '0'; return 1; }
    printf '%d' $(( (head_at - file_at) / 86400 ))
}

# -----------------------------------------------------------------------------
# Messages and identities
# -----------------------------------------------------------------------------

# git_trailers [rev-range]
#
# Every commit's trailers, one commit per line, tab-separated from its hash.
# Uses git's own trailer parser, which knows a trailer is a `Key: value` line
# in the final block. A grep cannot tell that from a commit whose body
# discusses one, and the difference decides whether a repository is considered
# contaminated.
#[pub]
# Usage: git_trailers [range] -> "<hash>\t<trailers>", one commit per line
git_trailers() {
    local range="${1:---all}"
    git log "$range" --format='%H%x09%(trailers:only=true,unfold=true)' 2>/dev/null
}

# git_identities [rev-range]
#
# Every distinct author and committer. What a forge's contributor list reads,
# and a field no message edit reaches.
#[pub]
# Usage: git_identities [range] -> every distinct author and committer
git_identities() {
    local range="${1:---all}"
    git log "$range" --format='%an <%ae>%n%cn <%ce>' 2>/dev/null | sort -u
}

# git_subjects <base>
#
# The subject line of every commit this branch adds. For checking conventions
# across a pull request without fetching it from a forge.
#[pub]
# Usage: git_subjects dev -> "<short-hash>\t<subject>" per commit added
git_subjects() {
    local base="$1"
    git log "${base}..HEAD" --format='%h%x09%s' 2>/dev/null
}

# git_tracked [pattern...]
#[pub]
# Usage: git_tracked ['*.sh'] -> one tracked path per line
git_tracked() {
    git ls-files "$@" 2>/dev/null
}
