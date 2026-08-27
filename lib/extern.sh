#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/extern.sh - Libraries from elsewhere
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 1: uses toml, xdg, fs, log and deps.
#
# A dependency is declared in `nut.toml`, not in the script that wants it:
#
#   [deps.shebang]
#   git = "https://github.com/orgrinrt/the-whole-shebang.git"
#   ref = "main"
#
# and a module inside it is reached by namespacing the use:
#
#   use shebang::diagnostics/findings
#
# Declared in the manifest rather than inline because a script that fetches its
# own dependencies decides for the whole project where code comes from, and
# does it somewhere nobody looks. One file answers "what does this project pull
# in", which is the question an auditor asks and the one a lockfile exists for.
#
# The bare form stays nutshell's own. nutshell is the default namespace, and
# prefixing the common path to disambiguate the rare one is friction on every
# line to help a few.
#
# Resolution is cached globally, keyed by url and ref, so several projects
# naming the same ref share one clone and the second project pays nothing. The
# same arrangement mockspace uses for engines, for the same reason.
#
# Usage:
#   use extern
#
#   extern_path shebang            # the checkout, fetching if needed
#   extern_resolve shebang/diagnostics/findings
# =============================================================================

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded: under a POSIX shell `nut_once` is not found, the `|| return
# 0` returns from the whole file, and the module then defines nothing while
# reporting success.
[ -n "${_NUTSHELL_EXTERN_SH:-}" ] && return 0
_NUTSHELL_EXTERN_SH=1

use toml string xdg fs log validate

# _extern_manifest
#
# The nearest `nut.toml`, from the script's own directory first and the working
# directory second.
#
# A script's dependencies belong to the script, the way a crate's belong to its
# Cargo.toml. Resolving from the working directory alone means a script run
# against some other repository cannot find its own manifest, and instead finds
# that repository's, or nothing. The interpreter knows where the script lives,
# so the unit that declares the `use` is the unit that answers for it.
#
# The working directory stays as the fallback, because a scratch script inside
# the project you are working in has no unit of its own and the project's
# manifest is the right answer for it.
_extern_manifest() {
    local start dir
    # The file that wrote the `use`, first. NUTSHELL_SCRIPT_DIR is unset on
    # purpose (a process that sources init would inherit an ancestor's), which
    # left only PWD: so a tool installed on PATH and run from anywhere else
    # could not find its own nut.toml, and every `use dep::x` in it failed.
    #
    # _NUT_ASKING_FROM is set per call by `use`, from BASH_SOURCE, so it says
    # which unit is asking rather than which process was started. Same
    # anchoring `super::` uses, for the same reason.
    for start in "${_NUT_ASKING_FROM:-}" "${NUTSHELL_SCRIPT_DIR:-}" "${PWD}"; do
        [ -z "$start" ] && continue
        dir="$start"
        while [ "$dir" != "/" ] && [ -n "$dir" ]; do
            [ -f "$dir/nut.toml" ] && { printf '%s' "$dir/nut.toml"; return 0; }
            dir="$(dirname "$dir")"
        done
    done
    return 1
}

# Where fetched dependencies live: one central, content-addressed store shared
# by every project on the machine, the same arrangement pnpm and yarn 2 settled
# on. Two projects on the same commit of the same dependency have one copy of
# it between them, and a project tree carries no dependency of its own.
#
# Under data rather than cache, deliberately. A cache is something a cleaner is
# entitled to delete at any moment; this is where the dependencies of every
# project on the machine actually live, and losing it offline breaks all of
# them at once. `NUTSHELL_STORE` overrides it.
_extern_cache_root() {
    if [ -n "${NUTSHELL_STORE:-}" ]; then
        printf '%s/externs' "${NUTSHELL_STORE%/}"
        return 0
    fi
    xdg_set_app_name nutshell
    printf '%s/externs' "$(xdg_app_data)"
}

# -----------------------------------------------------------------------------
# The lockfile
# -----------------------------------------------------------------------------
#
# `nut.lock` sits beside `nut.toml` and records the commit each dependency
# resolved to. `ref = "main"` names a branch, and a branch is a moving target:
# without this, two checkouts of the same project on the same day can be
# running different code, and neither can say so.
#
# It is written on first resolution and obeyed from then on. Moving to a newer
# commit is deliberate: delete the entry, or the file.
#
# Commit it. A lockfile in .gitignore records nothing anybody else can read.

_extern_lock_path() {
    local manifest
    manifest="$(_extern_manifest)" || return 1
    printf '%s/nut.lock' "${manifest%/*}"
}

#[pub]
# Usage: extern_locked shebang -> prints the pinned commit, or nothing
extern_locked() {
    local name="$1" lock
    lock="$(_extern_lock_path)" || return 1
    [ -f "$lock" ] || return 1
    toml_get "$lock" "deps.${name}.commit" 2>/dev/null
}

#[pub]
# Usage: extern_lock_write shebang <commit>
#
# Rewrites the whole file rather than editing one entry in place. It is
# generated, it is small, and a rewrite cannot corrupt a neighbouring entry the
# way a targeted edit can.
extern_lock_write() {
    local name="$1" commit="$2" lock existing tmp
    lock="$(_extern_lock_path)" || return 1

    tmp="${lock}.tmp.$$"
    {
        printf '# nut.lock - what each dependency resolved to. Generated; commit it.\n'
        printf '#\n'
        printf '# A commit or a tag in nut.toml is a pin, and this holds the checkout\n'
        printf '# there. A branch is a pin on that branch, meaning its head, and this\n'
        printf '# records what the head was and is rewritten whenever it moves.\n'

        # Every other entry, carried across unchanged.
        if [ -f "$lock" ]; then
            local other others
            others="$(grep -o '^\[deps\.[^]]*\]' "$lock" 2>/dev/null \
                      | sed 's/^\[deps\.//; s/\]$//')"
            while IFS= read -r other; do
                { [ -z "$other" ] || [ "$other" = "$name" ]; } && continue
                existing="$(toml_get "$lock" "deps.${other}.commit" 2>/dev/null)" || continue
                printf '\n[deps.%s]\ncommit = "%s"\n' "$other" "$existing"
            done <<EOF
$others
EOF
        fi

        printf '\n[deps.%s]\ncommit = "%s"\n' "$name" "$commit"
    } > "$tmp" || return 1

    mv -f "$tmp" "$lock"
}

#[pub]
# Usage: extern_declared shebang -> prints "<url> <ref>", or fails
extern_declared() {
    local name="$1" manifest url ref
    manifest="$(_extern_manifest)" || { log_error "no nut.toml above ${PWD}"; return 1; }

    url="$(toml_get "$manifest" "deps.${name}.git")" || {
        log_error "nut.toml declares no dependency named '${name}'"
        return 1
    }
    ref="$(toml_get "$manifest" "deps.${name}.ref" 2>/dev/null)"
    printf '%s %s' "$url" "${ref:-HEAD}"
}

# Resolved paths, by name, for the life of this process.
#
# Every `use <dep>::<module>` resolves the dependency again: the manifest is
# re-read, the lockfile re-read, the mirror and the worktree each asked whether
# git will answer for them. None of that can change while a script runs, and a
# program taking five modules out of one library paid it five times -- about
# four hundred milliseconds before anything of its own happened.
# What has been resolved this process.
#
# It reads as a working memo and has never been one: everything that writes to
# it is reached through a command substitution, so the assignment happens in a
# subshell and is gone when that returns. The per-process property callers
# actually get comes from `init`'s loaded-module table short-circuiting the
# `use` before this is reached.
#
# Left in place rather than deleted, because `extern_forget` is a public door
# onto it and removing that is a change for consumers. Marked so the next
# person to optimise this path does not find it and believe it.
# A `map` rather than an associative array, which is bash's. It holds one
# resolved directory per dependency name, so a `use` of a module from a unit
# already resolved costs a lookup rather than the whole walk again.
use map
map_new _EXTERN_RESOLVED

#[pub]
# Forget what has been resolved. For a caller that has changed a lockfile and
# wants the next lookup to see it, and for tests.
# Usage: extern_forget [name]
extern_forget() {
    if [ -n "${1:-}" ]; then map_del _EXTERN_RESOLVED "$1"; else map_clear _EXTERN_RESOLVED; fi
}

#[pub]
# Usage: extern_path shebang -> prints the checkout, fetching it once if needed
extern_path() {
    local name="$1" spec url ref mirror commit dir out

    local _er=""
    map_read _er _EXTERN_RESOLVED "$name"
    if [ -n "$_er" ]; then
        # Still checked, because a cached path whose checkout has been removed
        # is worse than no cache: the caller gets a directory git will not
        # answer for and no explanation.
        if _extern_is_repo "$_er"; then
            printf '%s' "$_er"
            return 0
        fi
        map_del _EXTERN_RESOLVED "$name"
    fi
    spec="$(extern_declared "$name")" || return 1
    url="${spec%% *}"
    ref="${spec##* }"

    mirror="$(_extern_mirror "$name" "$url" "$ref")" || return 1

    # What the ref means decides whether the lock has anything to say. A branch
    # is the remote's head of that branch now, so a recorded commit is a note
    # about the past rather than a pin, and the lock is written rather than
    # read. A tag or a revision names one commit, so the lock is the answer.
    local kind="" resolved=""
    if out="$(extern_resolve_ref "$url" "$ref")"; then
        kind="${out%% *}"; resolved="${out#* }"
    fi

    if [ "$kind" = "moving" ]; then
        commit="$resolved"
        extern_lock_write "$name" "$commit"
    else
        commit="$(extern_locked "$name")" || commit=""
        if [ -z "$commit" ]; then
            commit="${resolved:-$(_extern_ref_commit "$mirror" "$ref")}" || return 1
            [ -n "$commit" ] || return 1
            extern_lock_write "$name" "$commit"
        fi
    fi

    dir="$(_extern_cache_root)/$(_extern_key "${url}@${commit}")"
    # Whether it is a working checkout, not whether the path exists. A worktree
    # whose mirror has been deleted is still a directory, and returning it
    # handed the caller a path that git refuses to answer any question about,
    # permanently, with nothing to do about it but find the cache by hand.
    if ! _extern_is_repo "$dir"; then
        [ -e "$dir" ] && git -C "$mirror" worktree prune 2>/dev/null
        _extern_guard "$dir" _extern_lay_out "$name" "$mirror" "$url" "$commit" "$dir" || return 1
    fi

    map_set _EXTERN_RESOLVED "$name" "$dir"
    printf '%s' "$dir"
}

# _extern_lay_out <name> <mirror> <url> <commit> <dir>
_extern_lay_out() {
    local name="$1" mirror="$2" url="$3" commit="$4" dir="$5"

    # A shallow clone of a branch does not contain an older commit on it, and
    # taking an older commit is the ordinary case for a lockfile.
    git -C "$mirror" fetch --quiet origin "$commit" 2>/dev/null
    if ! git -C "$mirror" cat-file -e "${commit}^{commit}" 2>/dev/null; then
        log_error "${name} is locked to ${commit}, which ${url} does not have"
        log_error "delete its entry in nut.lock to take the newest commit instead"
        return 1
    fi
    fs_mkdir "${dir%/*}" || return 1

    # A worktree, not a second clone. Cloning the mirror was the obvious shape
    # and it does not work: a commit fetched by hash is reachable from no ref,
    # so a clone leaves it behind and the checkout fails on the exact commit
    # the lockfile asked for. A worktree reads the mirror's object store, where
    # it is.
    git -C "$mirror" worktree add --quiet --detach "$dir" "$commit" 2>/dev/null || {
        log_error "could not lay ${name} out at ${commit}"
        git -C "$mirror" worktree prune 2>/dev/null
        return 1
    }
}

_extern_key() { printf '%s' "$1" | cksum | tr -d ' '; }

# _extern_is_repo <dir> -> 0 when that directory is a working git checkout
#
# The readiness test for everything here. Both a mirror and a worktree are
# ready when git will answer a question about them, and neither is ready
# merely by existing.
_extern_is_repo() {
    git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

# _extern_guard <dir> <command...>
#
# Lay that directory out once, with one process doing it, and wait for whoever
# is already doing it rather than joining in.
#
# The cache is shared, so several processes resolving at once is the ordinary
# case rather than a corner: four of them on a cold cache had three fail with
# "could not fetch", because git was cloning into a directory another clone was
# already populating.
#
# Readiness is `_extern_is_repo`, never existence. Both defects this has had
# were the same mistake in different places: a waiter that returned as soon as
# the directory appeared handed back a path the winner was still writing into,
# and a guard that skipped the work because the directory existed left an
# interrupted fetch in place forever, since the empty directory it stopped for
# was exactly the thing that needed repairing.
#
# A partial directory is removed rather than left. Whatever is in it is the
# wreckage of a failed attempt, and keeping it only means the next call decides
# there is nothing to do.
#
# `mkdir` is the lock: one syscall, atomic on any filesystem worth the name,
# and no tool beyond the shell. The winner writes its pid inside, so a waiter
# can tell a working holder from a dead one and take over a corpse's lock at
# once instead of sitting out a clock. The age check stays as the fallback for
# a lock with no pid in it, since the alternative is a cache that stays wedged
# after one interrupted fetch.
# Not readonly. A caller, and the tests in particular, has to be able to say
# "do not wait eleven minutes for this one", and an assignment to a readonly
# fails silently enough that the first version of that test simply sat through
# the full wait.
_EXTERN_LOCK_STALE_MINUTES="${_EXTERN_LOCK_STALE_MINUTES:-10}"
_EXTERN_LOCK_WAIT_SECONDS="${_EXTERN_LOCK_WAIT_SECONDS:-660}"

_extern_guard() {
    local dir="$1"; shift
    local lock="${dir}.lock" waited=0

    # The parent, first. `mkdir "$lock"` is the lock, so it must not have a
    # second reason to fail: a missing parent directory failed it exactly the
    # way contention does, and the loop below then waited out the full eleven
    # minutes for a lock nobody was holding.
    mkdir -p "${lock%/*}" 2>/dev/null || true

    while ! mkdir "$lock" 2>/dev/null; do
        # Ready means ready, so a waiter never returns a half-written tree.
        _extern_is_repo "$dir" && return 0

        # A lock whose holder is dead. Taken over at once, because the process
        # that made it is gone and nothing else will clear it. `kill -0` asks
        # whether the pid is alive without signalling it; the cache is
        # per-user, so a permission refusal is not a concern here.
        local holder
        holder="$(cat "${lock}/pid" 2>/dev/null)"
        case "$holder" in ''|*[!0-9]*) holder="" ;; esac
        if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
            rm -rf "$lock"
            continue
        fi

        # A lock with no pid in it: brand new, mid-write, or left by hand.
        # Those age out on the clock instead.
        if [ -d "$lock" ] &&
           [ -z "$(find "$lock" -maxdepth 0 -mmin "-${_EXTERN_LOCK_STALE_MINUTES}" 2>/dev/null)" ]; then
            rm -rf "$lock"
            continue
        fi

        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -ge "$_EXTERN_LOCK_WAIT_SECONDS" ]; then
            log_error "waited ${waited}s for another process to lay out ${dir}"
            log_error "if nothing else is running, remove ${lock}"
            return 1
        fi
    done

    # `$BASHPID`, not `$$`.
    #
    # This runs inside a command substitution: `init` calls `extern_resolve`
    # in `$( )`, which calls `extern_path`, which calls this. `$$` in a
    # subshell is the *parent's* pid, so the lock recorded a process that
    # outlives the one holding it. A subshell that died mid-clone left a lock
    # naming a pid that `kill -0` still says is alive, and the takeover branch
    # below never fired: the next process sat out the full wait instead.
    printf '%s' "$BASHPID" > "${lock}/pid" 2>/dev/null

    local rc=0
    if ! _extern_is_repo "$dir"; then
        # Anything already here is the wreckage of an attempt that did not
        # finish, and git will not clone into a directory that is not empty.
        [ -e "$dir" ] && rm -rf "$dir"

        "$@" || rc=$?

        # The command reporting success is not the same as the directory being
        # usable, and the difference is what a later call would inherit.
        if [ "$rc" -eq 0 ] && ! _extern_is_repo "$dir"; then
            rc=1
            [ -e "$dir" ] && rm -rf "$dir"
        fi
    fi
    # Not rmdir: the lock holds the pid file now, and rmdir on a non-empty
    # directory fails silently here, which would leave every later caller
    # waiting on a lock whose holder finished long ago.
    rm -rf "$lock"
    return "$rc"
}

# _extern_mirror <name> <url> <ref> -> the fetch clone for that url and ref
#
# One clone per url and ref, shared between projects, because fetching the same
# repository once per project that names it is the cost the shared cache exists
# to avoid.
#
# Nothing reads code out of it. What a project gets back from `extern_path` is a
# separate checkout keyed by the resolved commit, so the mirror is free to move
# and no two projects are ever looking at one working tree.
#
# That separation is the whole point. With one shared checkout per url and ref,
# two projects locked to different commits took turns checking it out under each
# other: each got the commit it asked for at the moment it asked, and then read
# files from a directory the other had since moved.
_extern_mirror() {
    local name="$1" url="$2" ref="$3" dir
    dir="$(_extern_cache_root)/mirror-$(_extern_key "${url}@${ref}")"
    _extern_is_repo "$dir" && { printf '%s' "$dir"; return 0; }

    # validate rather than deps: deps tracks the unix text tools and their
    # variants, and git is not one of those.
    require_command git "fetching an external library needs git" || return 1
    fs_mkdir "${dir%/*}" || return 1

    _extern_guard "$dir" _extern_fetch "$name" "$url" "$ref" "$dir" || return 1
    printf '%s' "$dir"
}

# -----------------------------------------------------------------------------
# What a ref means
# -----------------------------------------------------------------------------
#
# Two kinds, and the difference is whether the ref moves. A branch names the
# remote's head of that branch, now, so the dependency comes up to it on every
# run. A tag or a revision names one commit forever.
#
# A branch pin that locks itself the first time is not a pin on a branch, it is
# a pin on whatever that branch happened to be. That is how a consumer ended up
# holding its dependency's first commit while months of work went past it, and
# the only symptom was a module that would not resolve.
#
# Asking the remote is a round trip, so the answer is kept for an hour: long
# enough that a script in a loop does not talk to the network every time, short
# enough that somebody who just pushed sees it on the next run.

EXTERN_BRANCH_TTL="${EXTERN_BRANCH_TTL:-3600}"

# What the remote calls this ref. Prints "heads <sha>" or "tags <sha>", and
# nothing when the remote has neither.
#
# The full refspec on both sides, because a bare name matches a tag as well as
# a branch and which one wins is otherwise down to the order the remote lists
# them. A branch wins where both exist: it is the one somebody meant to track.
_extern_remote_ref() {
    local url="$1" ref="$2" line sha
    [ -n "$ref" ] || return 1

    # Gathered first, then walked from a here-document. The loop cannot go on
    # the right of a pipe: it `return`s from this function on a match, and in a
    # subshell that returns from the subshell instead, so the function would
    # carry on past the answer it had already found.
    local heads
    heads="$(git ls-remote "$url" "refs/heads/${ref}" 2>/dev/null)"
    while IFS= read -r line; do
        case "$line" in *"refs/heads/${ref}") ;; *) continue ;; esac
        sha="${line%%[[:space:]]*}"
        [ -n "$sha" ] && { printf 'heads %s' "$sha"; return 0; }
    done <<EOF
$heads
EOF

    # `^{}` is the commit an annotated tag points at, and it is the one to
    # build from; the bare line is the tag object itself.
    #
    # Asked for with a trailing `*`, because the exact pattern does not return
    # the peeled line at all. `git ls-remote <url> refs/tags/0.1.0` gives one
    # row and it is the tag object; the `^{}` row only appears under a glob.
    # So this read the tag object every time, the `peeled` branch below never
    # ran, and a lockfile pinning an annotated tag recorded a sha that is not
    # a commit and can never equal any checkout's `HEAD`.
    #
    # Two exact patterns rather than a glob, so nothing but those two rows
    # can come back and the `case` below has nothing to filter out. A glob
    # would also return `0.1.0-rc1`, which is a door with no reason to open.
    # Gathered first for the same reason as the heads loop above, and with one
    # more: the body sets `peeled` and `plain` and the code after this reads
    # them, so on the right of a pipe both would be set in a subshell and read
    # back empty here.
    local peeled="" plain="" tags
    tags="$(git ls-remote "$url" "refs/tags/${ref}" "refs/tags/${ref}^{}" 2>/dev/null)"
    while IFS= read -r line; do
        sha="${line%%[[:space:]]*}"
        case "$line" in
            *"refs/tags/${ref}^{}") peeled="$sha" ;;
            *"refs/tags/${ref}")    plain="$sha"  ;;
        esac
    done <<EOF
$tags
EOF
    [ -n "$peeled" ] && { printf 'tags %s' "$peeled"; return 0; }
    [ -n "$plain" ]  && { printf 'tags %s' "$plain";  return 0; }
    return 1
}

# Where a branch resolution is remembered.
_extern_resolution_path() {
    printf '%s/branch-%s' "$(_extern_cache_root)" "$(_extern_key "${1}@${2}")"
}

_extern_read_resolution() {
    local f="$1" ts sha
    [ -r "$f" ] || return 1
    { IFS= read -r ts; IFS= read -r sha; } < "$f" || return 1
    [ -n "$sha" ] || return 1
    printf '%s %s' "${ts:-0}" "$sha"
}

# The remembered resolution, if it is younger than the window.
_extern_fresh_resolution() {
    local out ts sha now
    out="$(_extern_read_resolution "$1")" || return 1
    ts="${out%% *}"; sha="${out#* }"
    case "$ts" in ''|*[!0-9]*) return 1 ;; esac
    now="$(date -u +%s 2>/dev/null)" || return 1
    [ "$(( now - ts ))" -le "$EXTERN_BRANCH_TTL" ] || return 1
    printf '%s' "$sha"
}

# The remembered resolution whatever its age, for when the remote cannot be
# asked at all.
_extern_any_resolution() {
    local out; out="$(_extern_read_resolution "$1")" || return 1
    printf '%s' "${out#* }"
}

_extern_remember_resolution() {
    local f="$1" sha="$2"
    fs_mkdir "${f%/*}" 2>/dev/null || return 0
    printf '%s\n%s\n' "$(date -u +%s 2>/dev/null || printf 0)" "$sha" > "$f" 2>/dev/null || true
    return 0
}

#[pub]
# What a declared ref resolves to right now, and whether it can move.
#
# Prints "moving <sha>" for a branch and "fixed <sha>" for a tag or a
# revision. A branch is asked of the remote, at most once an hour. Offline, the
# last answer is used and said out loud: a revision that was the head an hour
# ago is very probably still in the cache, and running from it beats refusing
# to run on a machine somebody is in the middle of fixing.
# Where a fixed ref and the lockfile disagree, the lockfile wins and the
# checkout goes to the commit it names. That is what a lockfile is for and it is
# right when an upstream tag has moved under a project that already resolved it.
# It also means a hand-edited or damaged lock silently redirects a tag pin:
# nothing checks that the locked commit is reachable from the ref, and deleting
# the entry is how you ask for the ref to be resolved again.
# Usage: extern_resolve_ref <url> <ref> -> prints "moving <sha>" or "fixed <sha>"
extern_resolve_ref() {
    local url="$1" ref="$2" out kind sha f

    # A revision is itself, and asking a remote about it tells nobody anything.
    # Forty hex digits and nothing else. There is no `=~` here, so the length
    # is checked and then the content.
    _is_sha=0
    if [ "${#ref}" -eq 40 ]; then
        case "$ref" in *[!0-9a-fA-F]*) ;; *) _is_sha=1 ;; esac
    fi
    if [ "$_is_sha" -eq 1 ]; then
        printf 'fixed %s' "$ref"
        return 0
    fi

    f="$(_extern_resolution_path "$url" "$ref")"
    if sha="$(_extern_fresh_resolution "$f")"; then
        printf 'moving %s' "$sha"
        return 0
    fi

    if out="$(_extern_remote_ref "$url" "$ref")"; then
        kind="${out%% *}"; sha="${out#* }"
        if [ "$kind" = "heads" ]; then
            _extern_remember_resolution "$f" "$sha"
            printf 'moving %s' "$sha"
        else
            printf 'fixed %s' "$sha"
        fi
        return 0
    fi

    if sha="$(_extern_any_resolution "$f")"; then
        log_warn "could not ask ${url} about ${ref}; using the revision it named before" >&2
        printf 'moving %s' "$sha"
        return 0
    fi
    return 1
}

# Bring a mirror up to date with its ref. Best effort: a machine with no
# network still has whatever it cloned, and a stale answer beats no answer for
# a tool whose whole point is working on a machine that is broken.
_extern_refresh() {
    local mirror="$1" ref="$2"
    [ -n "$ref" ] || return 0
    # `--depth 1` because the mirror is only ever read at one commit, and the
    # clone that made it was shallow too.
    git -C "$mirror" fetch --quiet --depth 1 origin "$ref" 2>/dev/null || return 0
    return 0
}

# What a ref points at in a mirror. FETCH_HEAD first, since that is what the
# refresh just wrote; then the remote branch; then HEAD, which is the answer
# for a mirror that was cloned at a sha.
_extern_ref_commit() {
    local mirror="$1" ref="$2" c
    for c in FETCH_HEAD "origin/${ref}" "$ref" HEAD; do
        { [ -n "$ref" ] || [ "$c" = "HEAD" ]; } || continue
        if git -C "$mirror" rev-parse --verify --quiet "${c}^{commit}" >/dev/null 2>&1; then
            git -C "$mirror" rev-parse "${c}^{commit}" 2>/dev/null && return 0
        fi
    done
    return 1
}

# _extern_fetch <name> <url> <ref> <dir>
_extern_fetch() {
    local name="$1" url="$2" ref="$3" dir="$4"

    # To stderr: the caller's stdout is its return value, and a progress line
    # captured by command substitution becomes part of the path.
    log_info "fetching ${name} from ${url} (${ref})" >&2
    if ! git clone --quiet --depth 1 ${ref:+--branch "$ref"} "$url" "$dir" 2>/dev/null; then
        # A ref that is a sha rather than a branch cannot be cloned shallowly
        # by name, so fall back rather than reporting the repository missing.
        rm -rf "$dir"
        git clone --quiet "$url" "$dir" 2>/dev/null || {
            log_error "could not fetch ${name} from ${url}"
            rm -rf "$dir"
            return 1
        }
        git -C "$dir" checkout --quiet "$ref" 2>/dev/null || {
            log_error "${name} has no ref '${ref}'"
            rm -rf "$dir"
            return 1
        }
    fi
}

#[pub]
# Usage: extern_resolve shebang::diagnostics/findings -> prints the file path
#
# The path a namespaced `use` resolves to. Kept separate from loading so the
# resolution can be asked about, tested and reported on without sourcing
# anything, which is what an analyser needs.
extern_resolve() {
    local spec="$1" name rest root candidate
    name="${spec%%::*}"
    rest="${spec#*::}"
    [ "$name" = "$spec" ] && return 1

    # `::` separates modules the whole way down. A `/` is refused rather than
    # handed to the filesystem, which is what made it work by accident.
    _has_slash=0; case "$rest" in */*) _has_slash=1 ;; esac
    if [ "$_has_slash" -eq 1 ]; then
        _spec_fixed=""
        str_replace "$spec" "/" "::" _spec_fixed
        log_error "'${spec}' separates modules with '/'; use '::': ${_spec_fixed}"
        return 1
    fi
    local declared="${spec#*::}"
    str_replace "$rest" "::" "/" rest

    root="$(extern_path "$name")" || return 1

    # A library that declares its modules is answered from the declaration and
    # from nowhere else. Falling back to a search would put the guessing back
    # underneath the declaration, where a wrong entry resolves anyway and
    # nothing says so.
    if [ -r "${root}/lib.nut" ]; then
        local from_nut
        if from_nut="$(_lib_nut_lookup "$root" "$declared" public)"; then
            [ -f "$from_nut" ] && { printf '%s' "$from_nut"; return 0; }
            log_error "${name}'s lib.nut declares '${declared}' at ${from_nut#$root/}, which is not there"
            return 1
        fi
        log_error "'${declared}' is not among the modules ${name} declares"
        return 1
    fi

    # Two shapes, tried in order: a library laid out as `libs/<group>/<mod>.sh`,
    # and a flat `lib/<mod>.sh` like nutshell's own. Nothing else is guessed at,
    # because a resolver that searches widely finds the wrong file eventually.
    for candidate in "${root}/libs/${rest}.sh" "${root}/lib/${rest}.sh" "${root}/${rest}.sh"; do
        [ -f "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    done

    log_error "${name} has no module '${rest}'"
    return 1
}
