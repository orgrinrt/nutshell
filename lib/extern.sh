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

[[ -n "${_NUTSHELL_LIB_EXTERN_SH:-}" ]] && return 0
readonly _NUTSHELL_LIB_EXTERN_SH=1

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
    local name="$1" spec url ref key dir
    spec="$(extern_declared "$name")" || return 1
    url="${spec%% *}"
    ref="${spec##* }"

    # Keyed by url and ref together: two projects on the same ref share the
    # checkout, and two refs of the same repository do not collide.
    key="$(printf '%s@%s' "$url" "$ref" | cksum | tr -d ' ')"
    dir="$(_extern_cache_root)/${key}"

    if [[ ! -d "$dir/.git" ]]; then
        # validate rather than deps: deps tracks the unix text tools and their
        # variants, and git is not one of those.
        require_command git "fetching an external library needs git" || return 1
        fs_mkdir "${dir%/*}" || return 1

        # To stderr: this function's stdout is its return value, and a progress
        # line captured by command substitution becomes part of the path.
        log_info "fetching ${name} from ${url} (${ref})" >&2
        if ! git clone --quiet --depth 1 ${ref:+--branch "$ref"} "$url" "$dir" 2>/dev/null; then
            # A ref that is a sha rather than a branch cannot be cloned
            # shallowly by name, so fall back rather than reporting the
            # repository missing.
            git clone --quiet "$url" "$dir" 2>/dev/null || {
                log_error "could not fetch ${name} from ${url}"
                return 1
            }
            git -C "$dir" checkout --quiet "$ref" 2>/dev/null || {
                log_error "${name} has no ref '${ref}'"
                return 1
            }
        fi
    fi

    _extern_pin "$name" "$dir" "$url" || return 1
    printf '%s' "$dir"
}

# _extern_pin <name> <dir> <url>
#
# Hold the checkout at the locked commit, or record the one it is at.
#
# Checked on every resolution, not only on the fetch. The cache is shared
# between projects keyed by url and ref, so the checkout a project finds
# already there was placed by somebody else, and "we cloned it, so it is what
# we asked for" only holds the first time.
_extern_pin() {
    local name="$1" dir="$2" url="$3" locked head
    head="$(git -C "$dir" rev-parse HEAD 2>/dev/null)" || return 0

    locked="$(extern_locked "$name")" || {
        extern_lock_write "$name" "$head"
        return 0
    }
    [[ -z "$locked" || "$locked" == "$head" ]] && return 0

    # Fetch before checkout: a shallow clone of a branch does not contain an
    # older commit on it, and that is the ordinary case rather than an edge.
    git -C "$dir" fetch --quiet origin "$locked" 2>/dev/null
    git -C "$dir" checkout --quiet "$locked" 2>/dev/null || {
        log_error "${name} is locked to ${locked}, which ${url} does not have"
        log_error "delete its entry in nut.lock to take the newest commit instead"
        return 1
    }
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
