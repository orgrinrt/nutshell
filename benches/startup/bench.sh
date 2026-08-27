#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/startup - What a lowered form would save at load time
# =============================================================================
#
# Every `use` resolves through `_lib_nut_lookup`, and every caller of that
# wraps it in a command substitution, which is a fork. Add the manifest read
# per lookup and the predicate evaluation on top, and the cost sits in front of
# everything: it is paid before a single line of anybody's script runs.
#
# The proposal is a pre-process that lowers the source into a resolved form and
# runs that from a cache. This prices the ceiling of that idea before any of it
# is built: the lowered arm here is the crudest possible version, the files
# concatenated in the order the resolver would have loaded them, with no
# resolution left to do at all.
#
# It is a ceiling and not an estimate. A real lowering has to invalidate, has
# to key on the machine facts a predicate reads, and has to keep something a
# reader can debug. Whatever it costs, it cannot beat the number here.
#
# Usage:
#   ./bench startup [modules]
# =============================================================================

use bench

MODS="${1:-string log fs os toml}"

_ST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-st.XXXXXX")"
trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT

_ST_ROOT="${NUTSHELL_ROOT:-$PWD}"
_ST_LOWERED="$_ST_TMP/lowered.sh"

# The lowered form: what the resolver would have sourced, already sourced in.
#
# Crude on purpose. It resolves each module once, now, and concatenates. No
# `use` survives in it, so nothing forks at load time.
_st_lower() {
    local m file
    {
        printf 'nut_once() { return 0; }\n'
        printf 'use() { return 0; }\n'
        for m in $MODS; do
            file="$(_lib_nut_lookup "$_ST_ROOT" "$m" 2>/dev/null)" || continue
            printf '# --- %s ---\n' "$m"
            cat "$file"
        done
    } > "$_ST_LOWERED"
}

# The real path: a fresh shell, nutshell loaded, the modules used.
arm_resolved() {
    bash -c '
        . "$1"/init >/dev/null 2>&1 || exit 1
        shift
        for m in $1; do use "$m" >/dev/null 2>&1; done
        printf "%s" "$(str_upper ok)"
    ' _ "$_ST_ROOT" "$MODS" 2>/dev/null
}

# The lowered path: a fresh shell, one file.
arm_lowered() {
    bash -c '
        . "$1" >/dev/null 2>&1 || exit 1
        printf "%s" "$(str_upper ok)"
    ' _ "$_ST_LOWERED" 2>/dev/null
}

# The floor: a fresh shell that loads nothing, so the arms above can be read
# against what a shell costs before anybody asks it for anything.
arm_bare_shell() {
    bash -c 'printf "%s" "OK"' 2>/dev/null
}

_st_lower

_answer_of() { "$1"; }

bench_case "What a lowered form would save at load time"
bench_size "$(printf '%s\n' $MODS | wc -l | tr -d ' ')"
bench_verify _answer_of

bench_arm "resolved through the manifest" arm_resolved
bench_arm "lowered, one file"             arm_lowered
bench_arm "a bare shell, loading nothing" arm_bare_shell

bench_run || exit 1

printf '\n'
printf 'The lowered arm is a ceiling rather than an estimate: it is the files\n'
printf 'concatenated with nothing left to resolve, and no invalidation, no\n'
printf 'machine-fact key and nothing a reader could debug. A real lowering\n'
printf 'cannot beat it.\n'
printf '\n'
printf 'The bare shell is here so the other two can be read against what a\n'
printf 'shell costs before anybody asks it for anything. Without it a 2x\n'
printf 'between the first two could be almost all process startup.\n'
