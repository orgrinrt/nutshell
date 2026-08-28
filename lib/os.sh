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
# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded: under a POSIX shell `nut_once` is not found, the `|| return
# 0` returns from the whole file, and the module then defines nothing while
# reporting success. That is worse than failing, because the caller has no way
# to tell.
[ -n "${_NUTSHELL_OS_SH:-}" ] && return 0
_NUTSHELL_OS_SH=1

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

# Returns the OS name: linux|macos|windows|unknown
#[pub]
# Usage: os_name -> "linux", "macos", "windows" or "unknown"
os_name() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

#[pub]
# Returns 0 (true) if running on Linux, 1 (false) otherwise
# Usage: os_is_linux -> returns 0 on Linux, 1 elsewhere
os_is_linux() {
    case "$(uname -s)" in Linux*) return 0 ;; esac
    return 1
}

# Returns 0 (true) if running on macOS, 1 (false) otherwise
#[pub]
# Usage: os_is_macos -> returns 0 on macOS, 1 elsewhere
os_is_macos() {
    case "$(uname -s)" in Darwin*) return 0 ;; esac
    return 1
}

#[pub]
# Returns 0 (true) if running on Windows (via Cygwin/MSYS/MinGW), 1 (false) otherwise
# Usage: os_is_windows -> returns 0 under Cygwin, MSYS or MinGW, 1 elsewhere
os_is_windows() {
    case "$(uname -s)" in
        CYGWIN*|MINGW*|MSYS*) return 0 ;;
        *) return 1 ;;
    esac
}

#[allow(trivial_wrapper)]
# Returns the CPU architecture: x86_64|arm64|i686|armv7l|...
# Usage: os_arch -> "x86_64" | "arm64" | "i686" | "armv7l" | ...
#[pub]
os_arch() {
    uname -m
}

#[pub]
# Returns 0 if running in WSL, 1 otherwise
# Usage: os_is_wsl -> returns 0 under WSL, 1 elsewhere
os_is_wsl() {
    [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null
}
