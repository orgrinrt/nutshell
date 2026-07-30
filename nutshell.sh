#!/usr/bin/env bash
# =============================================================================
# nutshell.sh - Load every module at once
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# For when a script wants the whole library and would rather not list it:
#
#   source "path/to/nutshell/nutshell.sh"
#
# Prefer `init` and name what you use. It is the same loader either way, and a
# script that lists its modules says what it depends on:
#
#   . "path/to/nutshell/init"
#   use os log json
#
# This file used to be a third loader: it sourced every module by path in a
# hand-maintained layer order, kept its own copy of `use` and the loaded-module
# table, and carried a second version constant. The order duplicated dependency
# knowledge that now lives in each module's own `use` line, and the two copies
# of the loader had already drifted. It composes over `init` instead.
# =============================================================================

[[ -n "${_NUTSHELL_SH:-}" ]] && return 0
readonly _NUTSHELL_SH=1

_NUTSHELL_SH_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_NUTSHELL_SH_DIR" == "${BASH_SOURCE[0]}" ]] && _NUTSHELL_SH_DIR="."

# shellcheck source=/dev/null
source "$(cd "$_NUTSHELL_SH_DIR" && pwd)/init" || return 1

# Every module the library has, discovered rather than listed, so a new one is
# not missing from here until somebody remembers. Load order is `use`'s
# problem: a module declares what it needs and gets it.
_nutshell_load_all() {
    local mod
    while IFS= read -r mod; do
        [[ -z "$mod" ]] && continue
        use "$mod" || return 1
    done < <(nutshell_available)
}

_nutshell_load_all
