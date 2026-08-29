#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/hash.sh - Digests, and reading somebody's list of them
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0: shells out to whatever hashing tool the machine has.
#
# Generating a digest and reading one out of a file, and nothing else. Deciding
# whether a digest is *acceptable* is a policy question, and policy is not what
# this library is for: a caller comparing two strings knows what it wants to
# happen when they differ, and this does not.
#
# The whole difficulty is that the tool is named differently per system.
# `sha256sum` on linux, `shasum -a 256` on a mac, and neither on a stripped
# container, so the answer "there is no way to hash here" has to be
# distinguishable from "it hashed to nothing", which is why the exit codes are
# what they are.
#
# Usage:
#   use hash
#
#   sum="$(hash_sha256 ./file)" || echo "could not hash it"
#   hash_sums_get ./SHA256SUMS "thing.tar.gz"
# =============================================================================

[ -n "${_NUTSHELL_HASH_SH:-}" ] && return 0
_NUTSHELL_HASH_SH=1

use log

#[pub]
# Which tool this machine hashes with, or nothing.
# Usage: hash_impl -> "sha256sum" | "shasum" | "openssl" | ""
hash_impl() {
    if   command -v sha256sum >/dev/null 2>&1; then printf 'sha256sum'
    elif command -v shasum    >/dev/null 2>&1; then printf 'shasum'
    elif command -v openssl   >/dev/null 2>&1; then printf 'openssl'
    fi
}

#[pub]
# The sha256 of a file.
#
# **Three outcomes and three exit codes, because a caller has to tell them
# apart.** 0 with the digest on stdout; 2 when there is nothing here that can
# hash, which is a fact about the machine; 1 when the file cannot be read,
# which is a fact about the argument. Collapsing the last two is how "I could
# not check" gets reported as "it did not match".
# Usage: hash_sha256 <path> -> a lowercase hex digest
hash_sha256() {
    local path="${1:-}" impl out
    [ -n "$path" ] || return 1
    [ -r "$path" ] || { log_error "hash: nothing readable at ${path}"; return 1; }

    impl="$(hash_impl)"
    case "$impl" in
        sha256sum) out="$(sha256sum -- "$path" 2>/dev/null)" ;;
        shasum)    out="$(shasum -a 256 -- "$path" 2>/dev/null)" ;;
        openssl)   out="$(openssl dgst -sha256 -- "$path" 2>/dev/null)"
                   # `openssl dgst` writes `SHA256(path)= <digest>`, so the
                   # digest is the last field rather than the first.
                   out="${out##* }" ;;
        *) log_warn "hash: no sha256sum, shasum or openssl here"; return 2 ;;
    esac

    out="${out%% *}"
    [ -n "$out" ] || { log_error "hash: ${impl} produced nothing for ${path}"; return 1; }
    printf '%s' "$out"
}

#[pub]
# The digest a sums file gives for one name.
#
# The `<digest>  <name>` shape every one of these tools writes and reads. The
# separator is two spaces for a text read and a space and a star for a binary
# one, and both appear in the wild, so the name is matched off the end of the
# line rather than by splitting on a fixed separator.
#
# **A name that is not listed is not an error.** A sums file covering three of
# four files is an ordinary thing to publish, and the fourth is unlisted rather
# than wrong.
# Usage: hash_sums_get <sums file> <name> -> a digest, or nothing and 1
hash_sums_get() {
    local file="${1:-}" want="${2:-}" line name
    [ -n "$file" ] && [ -n "$want" ] || return 2
    [ -r "$file" ] || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        # Everything after the digest and its separator, with a binary-mode
        # star dropped if one is there.
        name="${line#* }"
        name="${name# }"
        name="${name#\*}"
        [ "$name" = "$want" ] || continue
        printf '%s' "${line%% *}"
        return 0
    done < "$file"
    return 1
}

#[pub]
# The same, from a sums file on stdin.
# Usage: printf '%s' "$body" | hash_sums_pick <name>
hash_sums_pick() {
    local want="${1:-}" line name
    [ -n "$want" ] || return 2
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        name="${line#* }"; name="${name# }"; name="${name#\*}"
        [ "$name" = "$want" ] || continue
        printf '%s' "${line%% *}"
        return 0
    done
    return 1
}
