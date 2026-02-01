#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/xdg.sh - XDG Base Directory Specification
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on os.sh and validate.sh
#
# PRINCIPLES:
#   - Single source of truth for ALL XDG directory paths
#   - NO SLIPPING - any code needing XDG paths MUST use this module
#   - NO DEFAULTS for app-specific values - FAIL if not configured
#   - Handles Linux, macOS, and Windows (WSL/Cygwin) differences
#
# REQUIRED:
#   XDG_APP_NAME must be set before calling xdg_app_* functions.
#   This is intentionally NOT defaulted - each application MUST configure it.
#
# Dependency chain: xdg.sh -> validate.sh -> log.sh -> os.sh
#
# XDG Base Directory Specification:
#   https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_XDG_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_XDG_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

_NUTSHELL_XDG_DIR="${BASH_SOURCE[0]%/*}"
source "${_NUTSHELL_XDG_DIR}/os.sh"
source "${_NUTSHELL_XDG_DIR}/validate.sh"

# -----------------------------------------------------------------------------
# XDG Base Directories (raw, without app name)
# These are safe to use without XDG_APP_NAME being set.
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Get XDG_DATA_HOME (user data files)
# Default: ~/.local/share (Linux), ~/Library/Application Support (macOS)
# Usage: xdg_data_home -> prints path
xdg_data_home() {
    if [[ -n "${XDG_DATA_HOME:-}" ]]; then
        echo "$XDG_DATA_HOME"
    elif os_is_macos; then
        echo "${HOME}/Library/Application Support"
    else
        echo "${HOME}/.local/share"
    fi
}

# @@PUBLIC_API@@
# Get XDG_CONFIG_HOME (user configuration)
# Default: ~/.config (Linux), ~/Library/Preferences (macOS)
# Usage: xdg_config_home -> prints path
xdg_config_home() {
    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        echo "$XDG_CONFIG_HOME"
    elif os_is_macos; then
        echo "${HOME}/Library/Preferences"
    else
        echo "${HOME}/.config"
    fi
}

# @@PUBLIC_API@@
# Get XDG_STATE_HOME (user state data - logs, history, etc.)
# Default: ~/.local/state (Linux), ~/Library/Application Support (macOS)
# Usage: xdg_state_home -> prints path
xdg_state_home() {
    if [[ -n "${XDG_STATE_HOME:-}" ]]; then
        echo "$XDG_STATE_HOME"
    elif os_is_macos; then
        echo "${HOME}/Library/Application Support"
    else
        echo "${HOME}/.local/state"
    fi
}

# @@PUBLIC_API@@
# Get XDG_CACHE_HOME (user cache data)
# Default: ~/.cache (Linux), ~/Library/Caches (macOS)
# Usage: xdg_cache_home -> prints path
xdg_cache_home() {
    if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
        echo "$XDG_CACHE_HOME"
    elif os_is_macos; then
        echo "${HOME}/Library/Caches"
    else
        echo "${HOME}/.cache"
    fi
}

# @@PUBLIC_API@@
# Get XDG_RUNTIME_DIR (runtime files - sockets, etc.)
# Default: $XDG_RUNTIME_DIR or $TMPDIR or /tmp
# Usage: xdg_runtime_dir -> prints path
xdg_runtime_dir() {
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        echo "$XDG_RUNTIME_DIR"
    else
        echo "${TMPDIR:-/tmp}"
    fi
}

# -----------------------------------------------------------------------------
# Application-specific directories
# REQUIRE XDG_APP_NAME to be set - will FAIL if not configured.
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Get application data directory
# Usage: xdg_app_data -> ~/.local/share/$XDG_APP_NAME
xdg_app_data() {
    require_set XDG_APP_NAME "XDG_APP_NAME must be set before using xdg_app_data"
    echo "$(xdg_data_home)/${XDG_APP_NAME}"
}

# @@PUBLIC_API@@
# Get application config directory
# Usage: xdg_app_config -> ~/.config/$XDG_APP_NAME
xdg_app_config() {
    require_set XDG_APP_NAME "XDG_APP_NAME must be set before using xdg_app_config"
    echo "$(xdg_config_home)/${XDG_APP_NAME}"
}

# @@PUBLIC_API@@
# Get application state directory
# Usage: xdg_app_state -> ~/.local/state/$XDG_APP_NAME
xdg_app_state() {
    require_set XDG_APP_NAME "XDG_APP_NAME must be set before using xdg_app_state"
    echo "$(xdg_state_home)/${XDG_APP_NAME}"
}

# @@PUBLIC_API@@
# Get application cache directory
# Usage: xdg_app_cache -> ~/.cache/$XDG_APP_NAME
xdg_app_cache() {
    require_set XDG_APP_NAME "XDG_APP_NAME must be set before using xdg_app_cache"
    echo "$(xdg_cache_home)/${XDG_APP_NAME}"
}

# @@PUBLIC_API@@
# Get application runtime directory
# Usage: xdg_app_runtime -> /run/user/$UID/$XDG_APP_NAME
xdg_app_runtime() {
    ensure_set XDG_APP_NAME "XDG_APP_NAME must be set before using xdg_app_runtime"
    echo "$(xdg_runtime_dir)/${XDG_APP_NAME}"
}

# -----------------------------------------------------------------------------
# Subdirectory helpers
# REQUIRE XDG_APP_NAME to be set.
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Get a subdirectory under app data
# Usage: xdg_app_data_subdir "backups" -> ~/.local/share/$XDG_APP_NAME/backups
xdg_app_data_subdir() {
    local subdir="${1:-}"
    local base
    base="$(xdg_app_data)"
    if [[ -n "$subdir" ]]; then
        echo "${base}/${subdir}"
    else
        echo "$base"
    fi
}

# @@PUBLIC_API@@
# Get a subdirectory under app config
# Usage: xdg_app_config_subdir "hosts" -> ~/.config/$XDG_APP_NAME/hosts
xdg_app_config_subdir() {
    local subdir="${1:-}"
    local base
    base="$(xdg_app_config)"
    if [[ -n "$subdir" ]]; then
        echo "${base}/${subdir}"
    else
        echo "$base"
    fi
}

# @@PUBLIC_API@@
# Get a subdirectory under app state
# Usage: xdg_app_state_subdir "logs" -> ~/.local/state/$XDG_APP_NAME/logs
xdg_app_state_subdir() {
    local subdir="${1:-}"
    local base
    base="$(xdg_app_state)"
    if [[ -n "$subdir" ]]; then
        echo "${base}/${subdir}"
    else
        echo "$base"
    fi
}

# @@PUBLIC_API@@
# Get a subdirectory under app cache
# Usage: xdg_app_cache_subdir "downloads" -> ~/.cache/$XDG_APP_NAME/downloads
xdg_app_cache_subdir() {
    local subdir="${1:-}"
    local base
    base="$(xdg_app_cache)"
    if [[ -n "$subdir" ]]; then
        echo "${base}/${subdir}"
    else
        echo "$base"
    fi
}

# -----------------------------------------------------------------------------
# Configuration helper
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Set the application name for XDG paths
# Usage: xdg_set_app_name "my-app"
# This MUST be called before using any xdg_app_* functions.
xdg_set_app_name() {
    local name="${1:-}"
    ensure_value "$name" "xdg_set_app_name: name cannot be empty"
    export XDG_APP_NAME="$name"
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Check if app name is configured
# Usage: xdg_has_app_name -> returns 0 if configured
xdg_has_app_name() {
    [[ -n "${XDG_APP_NAME:-}" ]]
}
