#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/startup - What a lowered form saves at load time
# =============================================================================
#
# Every `use` resolves through `_lib_nut_lookup`, every caller of that wraps it
# in a command substitution, and a fork is not cheap. The cost sits in front of
# everything: it is paid before a line of anybody's script runs.
#
# The lowered arm here resolves `use` **at lower time** rather than stubbing it
# out. That is the difference between this and the first version of this bench,
# which concatenated the named modules only, never loaded their dependencies,
# and reported a number that was partly the arm doing less work.
#
# So the closure is walked: each module's file is read, its own `use` lines
# resolved, and so on until nothing new appears. What is emitted is every file
# the resolver would have sourced, in the order it would have sourced them.
# `use` is a no-op in the result because by then there is nothing left for it
# to do, which is a fact about the lowering rather than a shortcut.
#
# **The arms are held to the same surface by the harness.** `bench_verify`
# compares the sorted list of every function defined, so an arm that loaded
# less is a disagreement and the run is refused rather than reported. The first
# version compared one function's output, and both arms answered `str_upper ok`
# identically while differing by 76 functions.
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

# Every module a file reaches for, as the resolver would read them.
#
# `super::x` inside a unit means x in that unit, and the manifest names it by
# its full path, so the prefix is dropped and the leaf looked up. That is what
# `_use_resolve` does and this has to agree with it or the closure is short.
_st_uses_in() {
    local file="$1" line m
    while IFS= read -r line; do
        case "$line" in
            *use[[:space:]]*) ;;
            *) continue ;;
        esac
        # Command position only. `# use foo` in prose is not a load.
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            use[[:space:]]*) ;;
            *) continue ;;
        esac
        line="${line#use }"
        for m in $line; do
            case "$m" in
                -*|'||'*|'&&'*|'{'*) continue ;;
            esac
            m="${m%%;*}"; m="${m%\"}"; m="${m#\"}"
            [[ -n "$m" ]] && printf '%s\n' "${m#super::}"
        done
    done < "$file"
}

# The closure, in load order: a module's dependencies before the module.
declare -A _ST_SEEN=()
declare -a _ST_ORDER=()
_st_walk() {
    local m="$1" file dep
    [[ -n "${_ST_SEEN[$m]:-}" ]] && return 0
    _ST_SEEN[$m]=1
    file="$(_lib_nut_lookup "$_ST_ROOT" "$m" 2>/dev/null)" || return 0
    while IFS= read -r dep; do
        [[ -n "$dep" ]] && _st_walk "$dep"
    done < <(_st_uses_in "$file")
    _ST_ORDER+=("$file")
}

_st_lower() {
    local m
    for m in $MODS; do _st_walk "$m"; done
    {
        # The interpreter still loads. A lowering removes the resolution, not
        # nutshell: `nut_once` and `use` have to exist because the files call
        # them, and by this point `use` has nothing left to resolve.
        printf '. "%s/init" >/dev/null 2>&1 || exit 1\n' "$_ST_ROOT"
        printf 'use() { return 0; }\n'
        for m in "${_ST_ORDER[@]}"; do
            printf '# --- %s ---\n' "${m#"$_ST_ROOT/"}"
            # The per-file inclusion guard goes.
            #
            # `nut_once` answers about the file being sourced, and concatenated
            # every file is the same file: the first call registers the lowered
            # one and every guard after it says "already loaded" and does
            # `return 0`, which returns from the whole thing. So the lowered
            # file defined the first module and nothing else, and the harness
            # refused the run because the arms disagreed by 130 functions.
            #
            # A real lowering strips them for the same reason. Inclusion is
            # decided at lower time; there is nothing left to guard at run
            # time, which is the point.
            sed -e 's/^nut_once || return 0$//' \
                -e 's/^nut_once || return$//' "$m"
        done
    } > "$_ST_LOWERED"
}

# Every function defined, sorted. The surface, not one call's answer.
_ST_PROBE='declare -F | sed "s/^declare -f //" | sort | tr "\n" " "'

arm_resolved() {
    bash -c '
        . "$1"/init >/dev/null 2>&1 || exit 1
        for m in $2; do use "$m" >/dev/null 2>&1; done
        eval "$3"
    ' _ "$_ST_ROOT" "$MODS" "$_ST_PROBE" 2>/dev/null
}

arm_lowered() {
    bash -c '. "$1" >/dev/null 2>&1 || exit 1; eval "$2"' \
        _ "$_ST_LOWERED" "$_ST_PROBE" 2>/dev/null
}

# The interpreter and nothing else, so the two above can be read against what
# is paid before any module is asked for at all.
arm_init_only() {
    bash -c '. "$1"/init >/dev/null 2>&1 || exit 1; printf init-only' \
        _ "$_ST_ROOT" 2>/dev/null
}

_st_lower

_answer_of() { "$1"; }

bench_case "What a lowered form saves at load time"
bench_size "${#_ST_ORDER[@]}"
bench_verify _answer_of

bench_arm "resolved through the manifest" arm_resolved
bench_arm "lowered, use resolved already" arm_lowered

bench_run || exit 1

printf '\n'
printf 'The closure is %s files for the %s modules named.\n' \
    "${#_ST_ORDER[@]}" "$(printf '%s\n' $MODS | wc -l | tr -d ' ')"
printf '\n'
printf 'The interpreter loads in both arms, so this is the resolution cost and\n'
printf 'not the cost of nutshell existing. `./bench startup` with one module\n'
printf 'shows how much of it is per-module rather than fixed.\n'
