#!/usr/bin/env bash
# =============================================================================
# nutshell.sh - Load all modules at once
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# This file sources ALL nutshell modules for convenience.
# For selective loading, use the init file instead:
#
#   . "${0%/*}/lib/nutshell/init"
#   use os log json
#
# Usage:
#   source "path/to/nutshell/nutshell.sh"
#
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_SH:-}" ]] && return 0
readonly _NUTSHELL_SH=1

# =============================================================================
# Version
# =============================================================================

readonly NUTSHELL_VERSION="0.1.0"
export NUTSHELL_VERSION

# =============================================================================
# Resolve nutshell root directory
# =============================================================================

NUTSHELL_ROOT="${BASH_SOURCE[0]%/*}"
# Handle case when sourced from same directory
[[ "$NUTSHELL_ROOT" == "${BASH_SOURCE[0]}" ]] && NUTSHELL_ROOT="."
NUTSHELL_ROOT="$(cd "$NUTSHELL_ROOT" && pwd)"
export NUTSHELL_ROOT

# Add bin to PATH for shebang support
export PATH="${NUTSHELL_ROOT}/bin:$PATH"

# =============================================================================
# Layer -1 (Foundation) - No dependencies
# =============================================================================

source "${NUTSHELL_ROOT}/lib/os.sh"
source "${NUTSHELL_ROOT}/lib/log.sh"
source "${NUTSHELL_ROOT}/lib/deps.sh"

# =============================================================================
# Layer 0 (Core) - May depend on foundation
# =============================================================================

source "${NUTSHELL_ROOT}/lib/color.sh"
source "${NUTSHELL_ROOT}/lib/validate.sh"
source "${NUTSHELL_ROOT}/lib/string.sh"
source "${NUTSHELL_ROOT}/lib/array.sh"
source "${NUTSHELL_ROOT}/lib/fs.sh"
source "${NUTSHELL_ROOT}/lib/text.sh"
source "${NUTSHELL_ROOT}/lib/toml.sh"
source "${NUTSHELL_ROOT}/lib/json.sh"
source "${NUTSHELL_ROOT}/lib/http.sh"
source "${NUTSHELL_ROOT}/lib/prompt.sh"
source "${NUTSHELL_ROOT}/lib/xdg.sh"

# =============================================================================
# Module tracking (for compatibility with use/init pattern)
# =============================================================================

declare -gA _NUTSHELL_LOADED=() 2>/dev/null || declare -A _NUTSHELL_LOADED=()
_NUTSHELL_LOADED[os]=1
_NUTSHELL_LOADED[log]=1
_NUTSHELL_LOADED[deps]=1
_NUTSHELL_LOADED[color]=1
_NUTSHELL_LOADED[validate]=1
_NUTSHELL_LOADED[string]=1
_NUTSHELL_LOADED[array]=1
_NUTSHELL_LOADED[fs]=1
_NUTSHELL_LOADED[text]=1
_NUTSHELL_LOADED[toml]=1
_NUTSHELL_LOADED[json]=1
_NUTSHELL_LOADED[http]=1
_NUTSHELL_LOADED[prompt]=1
_NUTSHELL_LOADED[xdg]=1

# Provide use() for scripts that expect it (no-op for already loaded modules)
use() {
    local mod
    for mod in "$@"; do
        if [[ -z "${_NUTSHELL_LOADED[$mod]:-}" ]]; then
            local mod_path="${NUTSHELL_ROOT}/lib/${mod}.sh"
            if [[ -f "$mod_path" ]]; then
                source "$mod_path"
                _NUTSHELL_LOADED[$mod]=1
            else
                echo "nutshell: unknown module '$mod'" >&2
                return 1
            fi
        fi
    done
}
export -f use

nutshell_loaded() {
    [[ -n "${_NUTSHELL_LOADED[$1]:-}" ]]
}
export -f nutshell_loaded

nutshell_modules() {
    local mod
    for mod in "${!_NUTSHELL_LOADED[@]}"; do
        echo "$mod"
    done | sort
}
export -f nutshell_modules
