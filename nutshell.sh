#!/usr/bin/env bash
# =============================================================================
# nutshell.sh - Main entry point
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Source this file to get all nutshell core modules at once.
#
# Usage:
#   source "path/to/nutshell/nutshell.sh"
#
# Or source individual modules:
#   source "path/to/nutshell/core/log.sh"
#   source "path/to/nutshell/core/string.sh"
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_SH:-}" ]] && return 0
readonly _NUTSHELL_SH=1

# -----------------------------------------------------------------------------
# Resolve nutshell root directory
# -----------------------------------------------------------------------------

NUTSHELL_ROOT="${BASH_SOURCE[0]%/*}"

# -----------------------------------------------------------------------------
# Layer -1 (Foundation) - No dependencies
# -----------------------------------------------------------------------------

source "${NUTSHELL_ROOT}/core/os.sh"
source "${NUTSHELL_ROOT}/core/log.sh"
source "${NUTSHELL_ROOT}/core/deps.sh"

# -----------------------------------------------------------------------------
# Layer 0 (Core) - May depend on foundation
# -----------------------------------------------------------------------------

source "${NUTSHELL_ROOT}/core/validate.sh"
source "${NUTSHELL_ROOT}/core/string.sh"
source "${NUTSHELL_ROOT}/core/array.sh"
source "${NUTSHELL_ROOT}/core/fs.sh"
source "${NUTSHELL_ROOT}/core/text.sh"
source "${NUTSHELL_ROOT}/core/toml.sh"
source "${NUTSHELL_ROOT}/core/xdg.sh"

# -----------------------------------------------------------------------------
# Export nutshell root for consumers
# -----------------------------------------------------------------------------

export NUTSHELL_ROOT
