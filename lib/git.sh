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
#   base="$(git_trunk dev main)"        # or git_trunk --remote
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

# git_branch [--show-current|--kind] [dir]
#
# The checked-out branch. A detached head has none, and the three forms say so
# in their own ways: the plain one answers `HEAD`, as it always has,
# `--show-current` answers nothing (git's own form, and what the clones that ask
# it raw expect), and `--kind` answers `branch` or `detached`. A repository with
# no commit yet is on a branch all the same and names it. Where the directory
# is not a repository every form fails.
#[pub]
# Usage: git_branch [--show-current|--kind] [dir] -> the branch, "HEAD" or "" detached, "branch"|"detached"
git_branch() {
    local mode=name
    case "${1:-}" in
        --show-current) mode=current; shift ;;
        --kind) mode=kind; shift ;;
    esac
    local dir="${1:-.}" name
    git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || return 1
    if name="$(git -C "$dir" symbolic-ref -q --short HEAD 2>/dev/null)"; then
        case "$mode" in kind) printf 'branch\n' ;; *) printf '%s\n' "$name" ;; esac
        return 0
    fi
    case "$mode" in
        name) printf 'HEAD\n' ;;
        kind) printf 'detached\n' ;;
    esac
    return 0
}

# git_trunk [-C <dir>] [--remote[=<name>] [--live] [--or-head]] [<preferred...>]
#
# The first named branch that exists, so a caller states its policy once and
# still works in a repository that has not adopted it yet. `git_trunk dev main`
# is this workspace's rule written down: dev is the trunk, main is the fallback
# for a repository that has only just joined.
#
# `--remote` asks the remote instead of the local branches: the first
# preferred branch the remote has (`dev main` where none is named). The
# remote is `origin` unless `=<name>` says otherwise, and it is read from the
# remote-tracking refs the clone already has;
# `--live` asks the remote itself, which needs the network, and gives up on a
# stalled one after `NUT_GIT_LIVE_TIMEOUT` seconds (see `_git_ls_remote`).
# Fails where there is no such remote or it has none of the preferred branches;
# `--or-head` instead answers the branch the remote's HEAD names then.
#[pub]
# Usage: git_trunk dev main -> the first of those that exists; git_trunk --remote -> the remote's dev, else main; --or-head adds its HEAD branch
git_trunk() {
    local dir=. remote="" live=0 or_head=0 candidate
    while [ $# -gt 0 ]; do
        case "$1" in
            -C) dir="${2:?-C wants a directory}"; shift 2 ;;
            --remote) remote=origin; shift ;;
            --remote=*) remote="${1#--remote=}"; shift ;;
            --live) live=1; shift ;;
            --or-head) or_head=1; shift ;;
            --) shift; break ;;
            *) break ;;
        esac
    done
    if [ -n "$remote" ]; then
        [ $# -gt 0 ] || set -- dev main
        _git_trunk_remote "$dir" "$remote" "$live" "$or_head" "$@"
        return
    fi
    for candidate in "$@"; do
        if git -C "$dir" rev-parse --verify "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# -----------------------------------------------------------------------------
# What changed
# -----------------------------------------------------------------------------
#
# Measured against the checkout, which is what a hook or a script standing in
# a branch wants. A review of somebody else's branch wants the branch rather
# than whatever happens to be checked out, so the helpers that read a tree or
# a range take the head they measure from `NUT_GIT_HEAD` where that is set,
# and `HEAD` otherwise:
#
#     NUT_GIT_HEAD=origin/feat/thing git_changed_files origin/dev
#
# The base is still the caller's; only the other end of the range moves. The
# covered set is `git_changed_files`, `git_changed`, `git_added_lines`,
# `git_file_age_days`, `git_subjects` and `git_tracked`; `git_trailers` takes
# its range as an argument, and everything else here asks about the repository
# rather than about a tree.

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
    git diff --name-only "${base}...${NUT_GIT_HEAD:-HEAD}" -- "$@" 2>/dev/null
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
    git diff "${base}...${NUT_GIT_HEAD:-HEAD}" -- "$path" 2>/dev/null | grep '^+' | grep -v '^+++'
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
    file_at=$(git log -1 --format=%ct "${NUT_GIT_HEAD:-HEAD}" -- "$path" 2>/dev/null)
    head_at=$(git log -1 --format=%ct "${NUT_GIT_HEAD:-HEAD}" 2>/dev/null)
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
    git log "${base}..${NUT_GIT_HEAD:-HEAD}" --format='%h%x09%s' 2>/dev/null
}

# git_tracked [pattern...]
#
# The index where the checkout is being measured; the named head's tree under
# `NUT_GIT_HEAD`, filtered by the same patterns, which match at any depth the
# way `ls-files` matches them.
#[pub]
# Usage: git_tracked ['*.sh'] -> one tracked path per line
git_tracked() {
    if [ -z "${NUT_GIT_HEAD:-}" ]; then
        git ls-files "$@" 2>/dev/null
        return
    fi
    local f p
    git ls-tree -r --name-only "$NUT_GIT_HEAD" 2>/dev/null | while IFS= read -r f; do
        if [ $# -eq 0 ]; then
            printf '%s\n' "$f"
            continue
        fi
        for p in "$@"; do
            # shellcheck disable=SC2254
            case "$f" in $p) printf '%s\n' "$f"; break ;; esac
        done
    done
}

# -----------------------------------------------------------------------------
# The trunk a remote has
# -----------------------------------------------------------------------------
#
# Answered from the remote-tracking refs a clone already has, or from the remote
# itself where the caller asks for the live answer. Written for a POSIX shell:
# no here-strings, no `$'..'`, and the remote's name only ever meets a shell
# pattern, never sed or a regular expression.

# _git_ls_remote <dir> <ls-remote args...>
#
# `git ls-remote` that cannot sit on a prompt or on a stalled connection for
# good. `NUT_GIT_LIVE_TIMEOUT` (seconds, 20 where unset or not a number) bounds
# a transfer that stalls (http, below 1000 bytes a second) and the connect of an
# ssh remote. It does not bound a TCP connect to an http host that drops its
# packets; that needs a process timeout, which nutshell has no module for yet.
_git_ls_remote() {
    local dir=$1 secs="${NUT_GIT_LIVE_TIMEOUT:-20}"; shift
    case "$secs" in ''|*[!0-9]*) secs=20 ;; esac
    if [ -z "${GIT_SSH_COMMAND:-}" ] && [ -z "${GIT_SSH:-}" ]; then
        GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME="$secs" \
            GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=$secs" \
            git -C "$dir" ls-remote "$@" 2>/dev/null
    else
        GIT_TERMINAL_PROMPT=0 GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME="$secs" \
            git -C "$dir" ls-remote "$@" 2>/dev/null
    fi
}

# _git_remote_branches <dir> <remote> <live>
#
# The branch names the remote has, one per line. Live asks the remote and fails
# where it cannot be reached; otherwise the remote-tracking refs answer, and
# fail where the remote is not configured.
_git_remote_branches() {
    local dir=$1 remote=$2 live=$3 out line ref
    if [ "$live" = 1 ]; then
        out="$(_git_ls_remote "$dir" --heads "$remote")" || return 1
        printf '%s\n' "$out" | while IFS= read -r line; do
            ref="${line#*[[:space:]]}"
            case "$ref" in refs/heads/*) printf '%s\n' "${ref#refs/heads/}" ;; esac
        done
        return 0
    fi
    git -C "$dir" remote get-url "$remote" >/dev/null 2>&1 || return 1
    git -C "$dir" for-each-ref --format='%(refname)' "refs/remotes/${remote}/" 2>/dev/null |
        while IFS= read -r ref; do
            ref="${ref#"refs/remotes/${remote}/"}"
            [ "$ref" = HEAD ] || printf '%s\n' "$ref"
        done
    return 0
}

# _git_remote_head <dir> <remote> <live>
#
# The branch the remote's HEAD names, or nothing where that is not known.
_git_remote_head() {
    local dir=$1 remote=$2 live=$3 out line
    if [ "$live" = 1 ]; then
        out="$(_git_ls_remote "$dir" --symref "$remote" HEAD)" || return 0
        printf '%s\n' "$out" | while IFS= read -r line; do
            case "$line" in
                "ref: refs/heads/"*)
                    line="${line#ref: refs/heads/}"
                    printf '%s' "${line%%[[:space:]]*}"
                    break ;;
            esac
        done
    else
        out="$(git -C "$dir" symbolic-ref -q "refs/remotes/${remote}/HEAD" 2>/dev/null)" || return 0
        printf '%s' "${out#"refs/remotes/${remote}/"}"
    fi
}

# _git_trunk_remote <dir> <remote> <live> <or_head> <candidates...>
#
# The first candidate the remote has. Where it has none, the branch its HEAD
# names if `or_head` is 1, else a failure. Fails too where the remote cannot be
# asked.
_git_trunk_remote() {
    local dir=$1 remote=$2 live=$3 or_head=$4; shift 4
    local have candidate head
    have="$(_git_remote_branches "$dir" "$remote" "$live")" || return 1
    for candidate in "$@"; do
        if printf '%s\n' "$have" | grep -qxF -- "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    [ "$or_head" = 1 ] || return 1
    head="$(_git_remote_head "$dir" "$remote" "$live")"
    [ -n "$head" ] || return 1
    printf '%s' "$head"
}

# -----------------------------------------------------------------------------
# What a clone holds that nobody else does
# -----------------------------------------------------------------------------
#
# The two questions that decide whether a clone can be thrown away.

# git_is_clean [dir]
#
# Whether the clone holds nothing uncommitted: no staged change, no unstaged
# change, no untracked file that is not ignored, and no stash. A stash counts as
# work: it is changes that no branch, remote or checkout carries, and removing
# the clone loses them. An ignored file alone is clean, since it is what a clone
# regenerates. A bare repository has no worktree to be dirty, so it is clean
# unless it has a stash. Exit 0 when clean, 1 when not, 2 where the directory is
# not a repository, so a caller can tell a dirty clone from a place that is not
# one.
#[pub]
# Usage: git_is_clean [dir] -> 0 clean, 1 uncommitted work or a stash, 2 not a repository
git_is_clean() {
    local dir="${1:-.}" out
    git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || return 2
    ! git -C "$dir" rev-parse -q --verify refs/stash >/dev/null 2>&1 || return 1
    [ "$(git -C "$dir" rev-parse --is-bare-repository 2>/dev/null)" != true ] || return 0
    out="$(git -C "$dir" status --porcelain 2>/dev/null)" || return 2
    [ -z "$out" ]
}

# _git_worktree_heads <dir>
#
# The commit every worktree of the repository stands on, the main one and each
# linked one, one per line: a detached head is on no branch, so the branch list
# does not see it. A bare entry and an unborn branch have none.
_git_worktree_heads() {
    local key val
    git -C "$1" worktree list --porcelain 2>/dev/null | while read -r key val; do
        [ "$key" = HEAD ] || continue
        case "$val" in *[!0]*) printf '%s\n' "$val" ;; esac
    done
}

# git_unpushed [dir]
#
# The commits this clone holds that no remote-tracking ref contains, one per
# line as `<hash><tab><subject>`: those reachable from a local branch or from
# the head of any worktree, detached or not, and then each stash entry. With no
# remote at all that is every commit. Tags are not read. A bare repository is
# read the same way, and has no remote-tracking refs unless it was set up to.
#[pub]
# Usage: git_unpushed [dir] -> "<hash>\t<subject>" per commit only this clone has; 2 where not a repository
git_unpushed() {
    local dir="${1:-.}" heads
    git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || return 2
    heads="$(_git_worktree_heads "$dir")"
    # shellcheck disable=SC2086
    git -C "$dir" log --branches $heads --not --remotes --format='%H%x09%s' 2>/dev/null
    git -C "$dir" stash list --format='%H%x09%s' 2>/dev/null
    return 0
}
