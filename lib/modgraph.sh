#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/modgraph.sh - The module graph, analysed once and cached
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 1: uses fs, xdg and log.
#
# What every module declares, defines and calls, in one table. Building it
# takes a pass over every file in a library, which is too slow to repeat for
# each question somebody wants to ask of it, so it is built once per distinct
# state of the library and cached globally. A second run against an unchanged
# library reads a file.
#
# Three facts per module, and every check downstream is a query over them:
#
#   declares  the modules it names in a `use` line
#   defines   the functions it introduces
#   calls     the module-prefixed functions it invokes
#
# The graph deliberately holds facts rather than judgements. Whether a cycle is
# a defect, whether an undeclared call is one, whether a module nothing uses
# should be deleted: those are the checker's opinions, and keeping them out of
# here means a second checker can hold different ones without rebuilding.
#
# Usage:
#   use modgraph
#
#   modgraph_build "/path/to/lib"        # cached; call freely
#   modgraph_modules                     # every module name
#   modgraph_declares  toml              # what toml said it uses
#   modgraph_defines   string            # what string introduces
#   modgraph_calls     toml              # prefixed functions toml invokes
#   modgraph_owner     str_trim          # which module defines it
#
# Environment:
#   MODGRAPH_NOCACHE - set to 1 to rebuild every time (for developing a check)
# =============================================================================

[[ -n "${_NUTSHELL_LIB_MODGRAPH_SH:-}" ]] && return 0
readonly _NUTSHELL_LIB_MODGRAPH_SH=1

use fs xdg log

declare -gA _MG_DECLARES=()
declare -gA _MG_DEFINES=()
declare -gA _MG_CALLS=()
declare -gA _MG_OWNER=()
declare -ga _MG_MODULES=()
_MG_ROOT=""

# -----------------------------------------------------------------------------
# Cache identity
# -----------------------------------------------------------------------------

# _mg_fingerprint <dir>
#
# What the library looks like right now. Names, sizes and modification times
# rather than content: reading every file to hash it would cost as much as the
# analysis the cache exists to avoid, and a file whose size and mtime are both
# unchanged has not been edited by anything this cache needs to notice.
_mg_fingerprint() {
    local dir="$1"
    { ls -1 "$dir"/*.sh 2>/dev/null | while IFS= read -r f; do
          printf '%s:%s:%s\n' "${f##*/}" "$(fs_size "$f" 2>/dev/null)" "$(fs_mtime "$f" 2>/dev/null)"
      done
    } | cksum | tr -d ' '
}

_mg_cache_file() {
    local dir="$1" print
    print="$(_mg_fingerprint "$dir")"
    xdg_set_app_name nutshell
    printf '%s/modgraph/%s.graph' "$(xdg_app_cache)" "$print"
}

# -----------------------------------------------------------------------------
# Reading a module
# -----------------------------------------------------------------------------

# _mg_scan <file> -> declares|defines|calls, one section per line
#
# One pass, three collections. Comments are stripped first so that a line
# discussing `use foo` does not read as one performing it, which is the same
# distinction that decides whether a repository looks contaminated.
_mg_scan() {
    local file="$1"
    local body
    body="$(sed -e 's/#.*$//' "$file" 2>/dev/null)"

    printf 'declares\t%s\n' "$(printf '%s\n' "$body" \
        | grep -oE '^[[:space:]]*use[[:space:]]+[a-z0-9_ -]+' \
        | sed -E 's/^[[:space:]]*use[[:space:]]+//' | tr ' ' '\n' \
        | grep -v '^$' | sort -u | tr '\n' ' ')"

    printf 'defines\t%s\n' "$(printf '%s\n' "$body" \
        | grep -oE '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)' \
        | sed -E 's/[[:space:]]*//; s/\(\)//' | sort -u | tr '\n' ' ')"

    printf 'calls\t%s\n' "$(printf '%s\n' "$body" \
        | grep -oE '\b_?[a-z][a-z0-9]*_[a-z0-9_]+\b' \
        | sort -u | tr '\n' ' ')"
}

# -----------------------------------------------------------------------------
# Building
# -----------------------------------------------------------------------------

_mg_reset() {
    _MG_DECLARES=(); _MG_DEFINES=(); _MG_CALLS=(); _MG_OWNER=(); _MG_MODULES=()
}

_mg_analyse() {
    local dir="$1" file mod line kind values
    for file in "$dir"/*.sh; do
        [[ -f "$file" ]] || continue
        mod="${file##*/}"; mod="${mod%.sh}"
        _MG_MODULES+=("$mod")
        while IFS=$'\t' read -r kind values; do
            case "$kind" in
                declares) _MG_DECLARES[$mod]="$values" ;;
                defines)  _MG_DEFINES[$mod]="$values" ;;
                calls)    _MG_CALLS[$mod]="$values" ;;
            esac
        done < <(_mg_scan "$file")

        local fn
        for fn in ${_MG_DEFINES[$mod]:-}; do
            _MG_OWNER[$fn]="$mod"
        done
    done
}

_mg_serialise() {
    local mod
    for mod in "${_MG_MODULES[@]}"; do
        printf 'M\t%s\t%s\t%s\t%s\n' "$mod" \
            "${_MG_DECLARES[$mod]:-}" "${_MG_DEFINES[$mod]:-}" "${_MG_CALLS[$mod]:-}"
    done
}

_mg_load() {
    local file="$1" tag mod declares defines calls fn
    _mg_reset
    while IFS=$'\t' read -r tag mod declares defines calls; do
        [[ "$tag" == "M" ]] || continue
        _MG_MODULES+=("$mod")
        _MG_DECLARES[$mod]="$declares"
        _MG_DEFINES[$mod]="$defines"
        _MG_CALLS[$mod]="$calls"
        for fn in $defines; do _MG_OWNER[$fn]="$mod"; done
    done < "$file"
}

# modgraph_build <lib-dir>
#
# Analyse the library, or read the analysis back if nothing has changed.
# @@PUBLIC_API@@
# Usage: modgraph_build "path/to/lib" -> populates the graph, returns 0
modgraph_build() {
    local dir="${1:-${NUTSHELL_ROOT}/lib}"
    _MG_ROOT="$dir"

    if [[ "${MODGRAPH_NOCACHE:-0}" == "1" ]]; then
        _mg_reset; _mg_analyse "$dir"; return 0
    fi

    local cache
    cache="$(_mg_cache_file "$dir")"
    if [[ -f "$cache" ]]; then
        _mg_load "$cache"
        return 0
    fi

    _mg_reset
    _mg_analyse "$dir"
    fs_mkdir "${cache%/*}" 2>/dev/null && _mg_serialise > "$cache" 2>/dev/null
    return 0
}

# -----------------------------------------------------------------------------
# Queries
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Usage: modgraph_modules -> prints every module name, one per line
modgraph_modules() { printf '%s\n' "${_MG_MODULES[@]}"; }

# @@PUBLIC_API@@
# Usage: modgraph_declares toml -> prints the modules toml names in a use line
modgraph_declares() { printf '%s' "${_MG_DECLARES[$1]:-}"; }

# @@PUBLIC_API@@
# Usage: modgraph_defines string -> prints the functions string introduces
modgraph_defines() { printf '%s' "${_MG_DEFINES[$1]:-}"; }

# @@PUBLIC_API@@
# Usage: modgraph_calls toml -> prints the prefixed functions toml invokes
modgraph_calls() { printf '%s' "${_MG_CALLS[$1]:-}"; }

# @@PUBLIC_API@@
# Usage: modgraph_owner str_trim -> prints the module defining it, if any
modgraph_owner() { printf '%s' "${_MG_OWNER[$1]:-}"; }

# -----------------------------------------------------------------------------
# Cycles
# -----------------------------------------------------------------------------

# modgraph_cycle
#
# One cycle if the declaration graph has any, as `a -> b -> a`. Depth-first
# with the path carried down, so what comes back is the route rather than the
# bare fact, and a reader can see which edge to cut.
#
# @@PUBLIC_API@@
# Usage: modgraph_cycle -> prints a cycle path, or nothing. Returns 1 if none.
modgraph_cycle() {
    local -A state=()
    local found=""

    _mg_visit() {
        local node="$1" path="$2" next
        [[ -n "$found" ]] && return
        case "${state[$node]:-}" in
            open)  found="$path"; return ;;  # path already ends at the repeat
            done)  return ;;
        esac
        state[$node]="open"
        for next in ${_MG_DECLARES[$node]:-}; do
            [[ -n "${_MG_DECLARES[$next]+set}" ]] || continue
            _mg_visit "$next" "${path} -> ${next}"
        done
        state[$node]="done"
    }

    local mod
    for mod in "${_MG_MODULES[@]}"; do
        [[ -n "$found" ]] && break
        [[ "${state[$mod]:-}" == "done" ]] && continue
        _mg_visit "$mod" "$mod"
    done

    unset -f _mg_visit
    [[ -z "$found" ]] && return 1
    printf '%s' "${found# -> }"
    return 0
}
