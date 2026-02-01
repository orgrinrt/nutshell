#!/usr/bin/env bash
# =============================================================================
# nutshell/core/os.sh - OS detection primitives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer -1 (Foundation): No dependencies. This is the bedrock.
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_OS_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_OS_SH=1

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

# Returns the OS name: linux|macos|windows|unknown
os_name() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

# Returns 0 (true) if running on Linux, 1 (false) otherwise
os_is_linux() {
    [[ "$(uname -s)" == Linux* ]]
}

# Returns 0 (true) if running on macOS, 1 (false) otherwise
os_is_macos() {
    [[ "$(uname -s)" == Darwin* ]]
}

# Returns 0 (true) if running on Windows (via Cygwin/MSYS/MinGW), 1 (false) otherwise
os_is_windows() {
    case "$(uname -s)" in
        CYGWIN*|MINGW*|MSYS*) return 0 ;;
        *) return 1 ;;
    esac
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Returns the CPU architecture: x86_64|arm64|i686|armv7l|...
# Usage: os_arch -> "x86_64" | "arm64" | "i686" | "armv7l" | ...
os_arch() {
    uname -m
}

# Returns 0 if running in WSL, 1 otherwise
os_is_wsl() {
    [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null
}
