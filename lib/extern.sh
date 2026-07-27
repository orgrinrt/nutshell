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

nut_once || return 0

use toml xdg fs log validate

# _extern_manifest
#
# The nearest `nut.toml`, walking up from the working directory. A project's
# dependencies belong to the project, so the answer is found from where the
# work is rather than from where nutshell happens to be installed.
_extern_manifest() {
    local dir="${PWD}"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/nut.toml" ]] && { printf '%s' "$dir/nut.toml"; return 0; }
        dir="$(dirname "$dir")"
    done
    return 1
}

_extern_cache_root() {
    xdg_set_app_name nutshell
    printf '%s/externs' "$(xdg_app_cache)"
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
    [[ -f "$lock" ]] || return 1
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
        printf '# nut.lock - resolved dependency commits. Generated; commit it.\n'
        printf '#\n'
        printf '# Delete an entry to take the newest commit on its ref again.\n'

        # Every other entry, carried across unchanged.
        if [[ -f "$lock" ]]; then
            local other
            while IFS= read -r other; do
                [[ -z "$other" || "$other" == "$name" ]] && continue
                existing="$(toml_get "$lock" "deps.${other}.commit" 2>/dev/null)" || continue
                printf '\n[deps.%s]\ncommit = "%s"\n' "$other" "$existing"
            done < <(grep -o '^\[deps\.[^]]*\]' "$lock" 2>/dev/null | sed 's/^\[deps\.//; s/\]$//')
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

#[pub]
# Usage: extern_path shebang -> prints the checkout, fetching it once if needed
extern_path() {
    local name="$1" spec url ref mirror commit dir
    spec="$(extern_declared "$name")" || return 1
    url="${spec%% *}"
    ref="${spec##* }"

    mirror="$(_extern_mirror "$name" "$url" "$ref")" || return 1

    commit="$(extern_locked "$name")" || commit=""
    if [[ -z "$commit" ]]; then
        commit="$(git -C "$mirror" rev-parse HEAD 2>/dev/null)" || return 1
        extern_lock_write "$name" "$commit"
    fi

    dir="$(_extern_cache_root)/$(_extern_key "${url}@${commit}")"
    # Whether it is a working checkout, not whether the path exists. A worktree
    # whose mirror has been deleted is still a directory, and returning it
    # handed the caller a path that git refuses to answer any question about,
    # permanently, with nothing to do about it but find the cache by hand.
    if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        [[ -e "$dir" ]] && { rm -rf "$dir"; git -C "$mirror" worktree prune 2>/dev/null; }
        _extern_guard "$dir" _extern_lay_out "$name" "$mirror" "$url" "$commit" "$dir" || return 1
    fi

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

# _extern_guard <dir> <command...>
#
# Run the command with one process at a time laying out that directory, and
# only if it is still absent by the time this process wins.
#
# The cache is shared, so several processes resolving at once is the ordinary
# case rather than a corner: four of them on a cold cache had three fail with
# "could not fetch", because `git clone` was writing into a directory another
# clone was already populating.
#
# `mkdir` is the lock. It is one syscall, it is atomic on every filesystem
# worth the name, and it needs no tool beyond the shell. A stale lock older
# than an hour is taken over, since the alternative is a cache that stays
# wedged after one interrupted fetch.
_extern_guard() {
    local dir="$1"; shift
    local lock="${dir}.lock" waited=0

    while ! mkdir "$lock" 2>/dev/null; do
        if [[ -d "$lock" ]] && [[ -z "$(find "$lock" -maxdepth 0 -mmin -60 2>/dev/null)" ]]; then
            rm -rf "$lock"
            continue
        fi
        sleep 1
        waited=$((waited + 1))
        if [[ "$waited" -ge 120 ]]; then
            log_error "gave up waiting for another process to lay out ${dir}"
            return 1
        fi
        # Somebody else finished it while this process waited.
        [[ -e "$dir" ]] && return 0
    done

    local rc=0
    if [[ ! -e "$dir" ]]; then
        "$@" || rc=$?
    fi
    rmdir "$lock" 2>/dev/null
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
    [[ -d "$dir/.git" ]] && { printf '%s' "$dir"; return 0; }

    # validate rather than deps: deps tracks the unix text tools and their
    # variants, and git is not one of those.
    require_command git "fetching an external library needs git" || return 1
    fs_mkdir "${dir%/*}" || return 1

    _extern_guard "$dir" _extern_fetch "$name" "$url" "$ref" "$dir" || return 1
    printf '%s' "$dir"
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
    [[ "$name" == "$spec" ]] && return 1

    root="$(extern_path "$name")" || return 1

    # Two shapes, tried in order: a library laid out as `libs/<group>/<mod>.sh`,
    # and a flat `lib/<mod>.sh` like nutshell's own. Nothing else is guessed at,
    # because a resolver that searches widely finds the wrong file eventually.
    for candidate in "${root}/libs/${rest}.sh" "${root}/lib/${rest}.sh" "${root}/${rest}.sh"; do
        [[ -f "$candidate" ]] && { printf '%s' "$candidate"; return 0; }
    done

    log_error "${name} has no module '${rest}'"
    return 1
}
