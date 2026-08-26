#!/usr/bin/env bash
# =============================================================================
# nutshell/checkcache - A check's answer for a file, kept until it can change
# =============================================================================
# Part of nutshell. https://github.com/orgrinrt/nutshell
#
# A check's finding about a file is a pure function of two things: the file,
# and the check that read it. Neither changes between two runs of the gate, and
# the overwhelming case is that nothing changed at all, so the overwhelming
# case should cost nothing.
#
# **The checker is part of the key, not just the file.** A check that gains a
# step, or tightens a threshold, has to read every file again; a cache over the
# file alone would keep answering with the old check's opinion and there would
# be no way to tell. The config counts for the same reason: the thresholds come
# out of `nut.toml` and they are what the answer was measured against.
#
# Freshness is decided with `-nt` rather than by hashing. A hash is a process
# per file, which is the cost this is trying to avoid; the file test is a stat
# the shell does itself. The trade is that touching a file without changing it
# re-runs the check, which is the harmless direction to be wrong in.
#
# Usage:
#   use checkcache
#
#   if nut_cache_hit "$check" "$file"; then
#       nut_cache_read "$check" "$file"      # the findings, as they were
#   else
#       findings="$(work_it_out "$file")"
#       nut_cache_write "$check" "$file" "$findings"
#   fi
# =============================================================================

[[ -n "${_NUTSHELL_CHECKCACHE_SH:-}" ]] && return 0
readonly _NUTSHELL_CHECKCACHE_SH=1

if ! declare -F use >/dev/null 2>&1; then
    printf 'nutshell: source nutshell first\n' >&2
    return 1
fi

# Off by default until a caller turns it on, because a cache that is wrong is
# worse than a check that is slow.
declare -g NUT_CACHE_ENABLED="${NUT_CACHE:-0}"

# Where an answer is kept. Under the store, beside the toolchains and externs,
# because it is derived data about this machine and not part of any project.
_nut_cache_root() {
    if [[ -n "${NUT_CACHE_DIR:-}" ]]; then
        printf '%s' "${NUT_CACHE_DIR%/}"
        return 0
    fi
    if declare -F nutshell_store_root >/dev/null 2>&1; then
        printf '%s/checks' "$(nutshell_store_root)"
        return 0
    fi
    printf '%s/nutshell/checks' "${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}"
}

# One file's answer, for one check. The path a source file flattens to.
_nut_cache_path() {
    local check="${1:-}" file="${2:-}" flat
    [[ -n "$check" && -n "$file" ]] || return 1
    flat="${file//\//_}"
    flat="${flat//[^A-Za-z0-9._-]/_}"
    printf '%s/%s/%s' "$(_nut_cache_root)" "${check//[^A-Za-z0-9._-]/_}" "$flat"
}

#[pub]
# Is there an answer for this file that nothing has invalidated?
#
# Fresh means newer than the file, newer than the check that produced it, and
# newer than the config the thresholds came from. Any of the three moving means
# the answer could be different and has to be worked out again.
# Usage: nut_cache_hit <check> <file> -> returns 0 on a usable answer
nut_cache_hit() {
    [[ "${NUT_CACHE_ENABLED:-0}" == "1" ]] || return 1
    local check="${1:-}" file="${2:-}" entry
    entry="$(_nut_cache_path "$check" "$file")" || return 1
    [[ -f "$entry" ]] || return 1
    [[ -e "$file" ]] || return 1
    [[ "$entry" -nt "$file" ]] || return 1

    # The check itself. Named by the caller, because only it knows which file
    # it is; a check that does not say cannot be cached.
    local src="${NUT_CACHE_CHECKER:-}"
    [[ -n "$src" && -e "$src" ]] || return 1
    [[ "$entry" -nt "$src" ]] || return 1

    # And the thresholds it measured against.
    if [[ -n "${CONFIG_FILE:-}" && -e "${CONFIG_FILE}" ]]; then
        [[ "$entry" -nt "$CONFIG_FILE" ]] || return 1
    fi
    return 0
}

#[pub]
# The answer that was kept. Nothing, and non-zero, when there is none.
# Usage: nut_cache_read <check> <file> -> prints what was cached
nut_cache_read() {
    local entry; entry="$(_nut_cache_path "$1" "$2")" || return 1
    [[ -r "$entry" ]] || return 1
    cat "$entry"
}

#[pub]
# Keep an answer. A failure to write is not a failure of the check: the run
# still has the answer, it just will not have it next time.
# Usage: nut_cache_write <check> <file> <findings>
nut_cache_write() {
    [[ "${NUT_CACHE_ENABLED:-0}" == "1" ]] || return 0
    local entry; entry="$(_nut_cache_path "$1" "$2")" || return 0
    mkdir -p "${entry%/*}" 2>/dev/null || return 0
    printf '%s' "${3:-}" > "$entry" 2>/dev/null || return 0
    return 0
}

#[pub]
# Throw the whole thing away.
# Usage: nut_cache_clear [check]
nut_cache_clear() {
    local root; root="$(_nut_cache_root)"
    if [[ -n "${1:-}" ]]; then
        rm -rf "${root}/${1//[^A-Za-z0-9._-]/_}"
    else
        rm -rf "$root"
    fi
    return 0
}
