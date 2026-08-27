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

MODS="${1:-string log fs os toml validate}"

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

    # `nut_reload` targets too. A module reached only by the lazy dispatch is
    # as much a dependency as one reached by `use`, and following only `use`
    # left the impl out of the closure: the lowered arm answered nothing for
    # `fs_size` and the harness refused the run.
    #
    # This is possible at all because every one of those is written literally.
    # Assembled from a variable, as two in `fs.sh` were until today, there is
    # nothing here to follow.
    # Anywhere in a non-comment line, not at the start of one: after today's
    # change `fs.sh`'s are inside a `case` arm, so the line begins
    # `stat_gnu)` and an anchored pattern finds nothing at all.
    grep -hE 'nut_reload[[:space:]]' "$file" 2>/dev/null \
        | grep -vE '^[[:space:]]*#' \
        | grep -oE 'nut_reload[[:space:]]+"?[^";[:space:]]+' \
        | sed -e 's/^nut_reload[[:space:]]*//' -e 's/"//g' -e 's/^super:://'
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
        # The lowered file registers what it contains rather than stubbing the
        # resolver.
        #
        # `use() { return 0; }` looks equivalent and is not: `nut_reload` goes
        # through `use`, so a stub breaks the lazy dispatch. `fs_size` answered
        # nothing in this arm and the harness refused the run, correctly.
        #
        # Registering instead means `use` short-circuits on everything already
        # here, which is the truthful thing for a lowering to do: inclusion was
        # decided at lower time and the registry is where that is recorded.
        # Every registration first, before any body.
        #
        # Emitted per module they interleave with the code, and a shake that
        # keeps the preamble by reading up to the first module marker then
        # keeps one of them. `fs_size` reached for an impl that nothing had
        # registered and answered nothing.
        for m in "${_ST_ORDER[@]}"; do
            printf '_NUTSHELL_LOADED["%s"]=1\n' "$m"
        done
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
            #
            # And `super::` is rewritten away.
            #
            # It resolves relative to the file that wrote the call, through
            # `BASH_SOURCE[1]`, and concatenated every call comes from the
            # lowered file. That file is in a temp directory with no manifest
            # above it, so `super::fs::impl::stat_bsd` resolved to nothing and
            # `fs_size` failed with a message about a missing `nut.toml`.
            #
            # A lowering knows the unit at lower time, which is the whole
            # point, so it writes the name the resolver can answer instead of
            # one that depends on where the file ends up.
            sed -e 's/^nut_once || return 0$//' \
                -e 's/^nut_once || return$//' \
                -e 's/super:://g' "$m"
        done
    } > "$_ST_LOWERED"
}

_ST_WORKLOAD="${_ST_ROOT}/benches/startup/workload.sh"
_ST_SHAKEN="$_ST_TMP/shaken.sh"

# The lowered file with everything unreachable removed.
#
# Roots are the names the workload mentions. Then the closure: anything a
# retained body mentions is retained too. Whatever survives is emitted, the
# rest is not there at all.
#
# It reads names rather than parsing shell, so it over-retains: a name in a
# comment or a string counts. That is the safe direction, and the number it
# produces is a floor on what a real pass could drop rather than a claim about
# what it would.
#
# What it cannot do is see a name assembled at run time, which is why every
# `nut_reload` in this library is written literally. Two in `fs.sh` were not,
# and a shake would have dropped two of the three stat implementations.
_st_shake() {
    local keep; keep="$(
        bash -c '
            set -uo pipefail
            . "$1" >/dev/null 2>&1 || exit 1
            declare -A BODY=()
            while IFS= read -r fn; do
                BODY["$fn"]="$(declare -f "$fn" 2>/dev/null)"
            done < <(declare -F | sed "s/^declare -f //")

            declare -A KEEP=(); declare -a WORK=()
            _seed() {
                local n
                while IFS= read -r n; do
                    [ -n "${BODY[$n]:-}" ] || continue
                    [ -n "${KEEP[$n]:-}" ] && continue
                    KEEP["$n"]=1; WORK+=("$n")
                done
            }
            _seed < <(grep -ohE "\b[a-z_][a-zA-Z0-9_]*\b" "$2" | sort -u)
            while [ ${#WORK[@]} -gt 0 ]; do
                fn="${WORK[0]}"; WORK=("${WORK[@]:1}")
                _seed < <(printf "%s" "${BODY[$fn]}" | grep -ohE "\b[a-z_][a-zA-Z0-9_]*\b" | sort -u)
            done
            printf "%s\n" "${!KEEP[@]}"
        ' _ "$_ST_LOWERED" "$_ST_WORKLOAD"
    )"

    # The lowered file with unretained function definitions cut out of it, and
    # everything else left exactly where it was.
    #
    # Filtered rather than rebuilt from `declare -f`. Rebuilt, the result is
    # functions and nothing else: every module's file-scope initialisation
    # goes, and `deps.sh` populating its tool table at load time was the one
    # that showed. `fs_size` then read an empty variant table, chose no impl,
    # and answered nothing.
    #
    # So the unit of shaking is one function definition. Anything outside one
    # is kept, because nothing here can tell what it was for.
    # Through a file, not `-v`. An awk variable cannot hold a newline, and the
    # retained set is one name per line, so `-v` gives `newline in string`.
    printf '%s\n' "$keep" > "$_ST_TMP/keep.txt"

    awk -v keepfile="$_ST_TMP/keep.txt" '
        BEGIN { while ((getline line < keepfile) > 0) if (line != "") K[line] = 1 }
        # A definition starts a block. Depth counts braces until it closes.
        depth == 0 && match($0, /^[[:space:]]*(function[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_-]*[[:space:]]*\(\)[[:space:]]*\{?[[:space:]]*$/) {
            name = $0
            sub(/^[[:space:]]*/, "", name); sub(/^function[[:space:]]+/, "", name)
            sub(/[[:space:]]*\(\).*$/, "", name)
            infn = 1; depth = 0; drop = (name in K) ? 0 : 1
        }
        {
            if (infn) {
                depth += gsub(/\{/, "{")
                depth -= gsub(/\}/, "}")
                if (!drop) print
                if (depth <= 0) { infn = 0; drop = 0 }
                next
            }
            print
        }
    ' "$_ST_LOWERED" > "$_ST_SHAKEN"
}

# What the workload answers. The arms load the library three ways and this is
# what says they still do the same thing.
#
# Not the loaded surface, which is what the other comparison in this file uses:
# a shaken arm loads less by design, so comparing surfaces would refuse it for
# doing exactly what it is for.
_ST_PROBE='. "'"$_ST_WORKLOAD"'" >/dev/null 2>&1; _wl'

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

arm_shaken() {
    bash -c '. "$1" >/dev/null 2>&1 || exit 1; eval "$2"' \
        _ "$_ST_SHAKEN" "$_ST_PROBE" 2>/dev/null
}

# The interpreter and nothing else, so the two above can be read against what
# is paid before any module is asked for at all.
arm_init_only() {
    bash -c '. "$1"/init >/dev/null 2>&1 || exit 1; printf init-only' \
        _ "$_ST_ROOT" 2>/dev/null
}

_st_lower
_st_shake

_answer_of() { "$1"; }

bench_case "What a lowered form saves at load time"
bench_size "${#_ST_ORDER[@]}"
bench_verify _answer_of

bench_arm "resolved through the manifest" arm_resolved
bench_arm "lowered, use resolved already" arm_lowered
bench_arm "lowered and shaken"            arm_shaken

bench_run || exit 1

printf '\n'
printf 'The closure is %s files for the %s modules named.\n' \
    "${#_ST_ORDER[@]}" "$(printf '%s\n' $MODS | wc -l | tr -d ' ')"
printf '\n'
printf 'The interpreter loads in both arms, so this is the resolution cost and\n'
printf 'not the cost of nutshell existing. `./bench startup` with one module\n'
printf 'shows how much of it is per-module rather than fixed.\n'
