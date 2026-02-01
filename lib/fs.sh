#!/usr/bin/env bash
# =============================================================================
# nutshell/core/fs.sh - Filesystem primitives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on deps.sh for tool detection
#
# This module provides filesystem operations. Functions that require
# external tools with variant differences (like stat) use lazy-init stubs
# that, on first call, select and source the appropriate implementation.
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_FS_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_FS_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

_NUTSHELL_FS_DIR="${BASH_SOURCE[0]%/*}"
# Handle case when sourced from same directory (BASH_SOURCE[0] has no path component)
[[ "$_NUTSHELL_FS_DIR" == "${BASH_SOURCE[0]}" ]] && _NUTSHELL_FS_DIR="."
source "${_NUTSHELL_FS_DIR}/deps.sh"

# Path to impl directory
readonly _FS_IMPL_DIR="${_NUTSHELL_FS_DIR}/fs/impl"

# -----------------------------------------------------------------------------
# Module status
# -----------------------------------------------------------------------------

_FS_READY=0
_FS_ERROR=""

# Check that we have basic filesystem tools
if deps_has_any "stat" "perl"; then
    _FS_READY=1
else
    _FS_ERROR="No stat tool available (need stat or perl)"
fi

# -----------------------------------------------------------------------------
# Existence checks (pure bash; no external tools needed)
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Check if path exists (file or directory)
# Usage: fs_exists "path" -> returns 0 (true) or 1 (false)
fs_exists() {
    [[ -e "${1:-}" ]]
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Check if path is a regular file
# Usage: fs_is_file "path" -> returns 0 (true) or 1 (false)
fs_is_file() {
    [[ -f "${1:-}" ]]
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Check if path is a directory
# Usage: fs_is_dir "path" -> returns 0 (true) or 1 (false)
fs_is_dir() {
    [[ -d "${1:-}" ]]
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Check if path is a symbolic link
# Usage: fs_is_link "path" -> returns 0 (true) or 1 (false)
fs_is_link() {
    [[ -L "${1:-}" ]]
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Check if file is readable
# Usage: fs_is_readable "path" -> returns 0 (true) or 1 (false)
fs_is_readable() {
    [[ -r "${1:-}" ]]
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Check if file is writable
# Usage: fs_is_writable "path" -> returns 0 (true) or 1 (false)
fs_is_writable() {
    [[ -w "${1:-}" ]]
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Check if file is executable
# Usage: fs_is_executable "path" -> returns 0 (true) or 1 (false)
fs_is_executable() {
    [[ -x "${1:-}" ]]
}

# @@PUBLIC_API@@
# @@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@
# Check if file is non-empty
# Usage: fs_is_nonempty "path" -> returns 0 (true) or 1 (false)
fs_is_nonempty() {
    [[ -s "${1:-}" ]]
}

# -----------------------------------------------------------------------------
# Directory operations (standard tools)
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Create directory (and parents) if it doesn't exist
# Usage: fs_mkdir "/path/to/dir" -> returns 0 on success
fs_mkdir() {
    local path="${1:-}"
    [[ -z "$path" ]] && return 1
    [[ -d "$path" ]] && return 0
    mkdir -p "$path"
}

# -----------------------------------------------------------------------------
# File operations (standard tools)
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Remove file or directory (safe - doesn't fail if missing)
# Usage: fs_rm "/path/to/remove" -> returns 0 on success
fs_rm() {
    local path="${1:-}"
    [[ -z "$path" ]] && return 1
    [[ ! -e "$path" ]] && return 0
    rm -rf "$path"
}

# @@PUBLIC_API@@
# Copy file or directory
# Usage: fs_cp "source" "dest" -> returns 0 on success
fs_cp() {
    local src="${1:-}"
    local dst="${2:-}"
    [[ -z "$src" || -z "$dst" ]] && return 1
    [[ ! -e "$src" ]] && return 1
    cp -r "$src" "$dst"
}

# @@PUBLIC_API@@
# Move file or directory
# Usage: fs_mv "source" "dest" -> returns 0 on success
fs_mv() {
    local src="${1:-}"
    local dst="${2:-}"
    [[ -z "$src" || -z "$dst" ]] && return 1
    [[ ! -e "$src" ]] && return 1
    mv "$src" "$dst"
}

# -----------------------------------------------------------------------------
# Path manipulation (pure bash + standard tools)
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Get absolute path (resolves symlinks)
# Usage: fs_realpath "relative/path" -> "/absolute/path"
fs_realpath() {
    local path="${1:-}"
    [[ -z "$path" ]] && return 1
    
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd -P)
    elif [[ -f "$path" ]]; then
        local dir base
        dir="$(cd "$(dirname "$path")" && pwd -P)"
        base="$(basename "$path")"
        echo "${dir}/${base}"
    else
        # Path doesn't exist - resolve what we can
        local dir base
        dir="$(dirname "$path")"
        base="$(basename "$path")"
        if [[ -d "$dir" ]]; then
            echo "$(cd "$dir" && pwd -P)/${base}"
        else
            echo "$path"
        fi
    fi
}

# @@PUBLIC_API@@
# Get directory portion of path
# Usage: fs_dirname "/path/to/file" -> "/path/to"
fs_dirname() {
    local path="${1:-}"
    [[ -z "$path" ]] && return 1
    dirname "$path"
}

# @@PUBLIC_API@@
# Get filename portion of path
# Usage: fs_basename "/path/to/file.txt" -> "file.txt"
fs_basename() {
    local path="${1:-}"
    [[ -z "$path" ]] && return 1
    basename "$path"
}

# @@PUBLIC_API@@
# Get file extension
# Usage: fs_extension "file.txt" -> "txt"
fs_extension() {
    local path="${1:-}"
    local base
    base="$(basename "$path")"
    
    # No extension if no dot or starts with dot
    [[ "$base" != *.* ]] && return 0
    [[ "$base" == .* && "${base#.}" != *.* ]] && return 0
    
    echo "${base##*.}"
}

# @@PUBLIC_API@@
# Get filename without extension
# Usage: fs_basename_no_ext "file.txt" -> "file"
fs_basename_no_ext() {
    local path="${1:-}"
    local base
    base="$(basename "$path")"
    
    # No extension to remove
    [[ "$base" != *.* ]] && { echo "$base"; return 0; }
    [[ "$base" == .* && "${base#.}" != *.* ]] && { echo "$base"; return 0; }
    
    echo "${base%.*}"
}

# -----------------------------------------------------------------------------
# File information - LAZY INIT STUBS
# These stubs select and source the best implementation on first call
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Get file size in bytes
# Usage: fs_size "/path/to/file" -> "12345"
fs_size() {
    # First call: decide which implementation to use
    local impl=""
    
    if deps_has "stat"; then
        local variant="${_TOOL_VARIANT[stat]:-unknown}"
        case "$variant" in
            gnu)     impl="stat_gnu.sh" ;;
            bsd)     impl="stat_bsd.sh" ;;
            *)
                # Unknown variant; try perl if available
                if deps_has "perl"; then
                    impl="perl_stat.sh"
                else
                    # Guess based on OS
                    case "$(uname -s)" in
                        Darwin*) impl="stat_bsd.sh" ;;
                        *)       impl="stat_gnu.sh" ;;
                    esac
                fi
                ;;
        esac
    elif deps_has "perl"; then
        impl="perl_stat.sh"
    fi
    
    if [[ -n "$impl" ]]; then
        source "${_FS_IMPL_DIR}/${impl}"
    else
        # No tool available
        fs_size() {
            echo "[ERROR] fs_size: no stat tool available" >&2
            return 1
        }
    fi
    
    # Call the now-replaced function
    fs_size "$@"
}

# @@PUBLIC_API@@
# Get file modification time (epoch seconds)
# Usage: fs_mtime "/path/to/file" -> "1234567890"
fs_mtime() {
    # First call: decide which implementation to use
    local impl=""
    
    if deps_has "stat"; then
        local variant="${_TOOL_VARIANT[stat]:-unknown}"
        case "$variant" in
            gnu)     impl="stat_gnu.sh" ;;
            bsd)     impl="stat_bsd.sh" ;;
            *)
                if deps_has "perl"; then
                    impl="perl_stat.sh"
                else
                    case "$(uname -s)" in
                        Darwin*) impl="stat_bsd.sh" ;;
                        *)       impl="stat_gnu.sh" ;;
                    esac
                fi
                ;;
        esac
    elif deps_has "perl"; then
        impl="perl_stat.sh"
    fi
    
    if [[ -n "$impl" ]]; then
        source "${_FS_IMPL_DIR}/${impl}"
    else
        fs_mtime() {
            echo "[ERROR] fs_mtime: no stat tool available" >&2
            return 1
        }
    fi
    
    # Call the now-replaced function
    fs_mtime "$@"
}

# -----------------------------------------------------------------------------
# Temporary files (standard tools)
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Create a temporary file and print its path
# Usage: fs_temp_file [prefix] -> "/tmp/prefix.XXXXXX"
fs_temp_file() {
    local prefix="${1:-tmp}"
    
    if deps_has "mktemp"; then
        "${_TOOL_PATH[mktemp]}" "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
    else
        # Fallback using $$ and RANDOM
        local path="${TMPDIR:-/tmp}/${prefix}.${$}.${RANDOM}"
        touch "$path" && echo "$path"
    fi
}

# @@PUBLIC_API@@
# Create a temporary directory and print its path
# Usage: fs_temp_dir [prefix] -> "/tmp/prefix.XXXXXX"
fs_temp_dir() {
    local prefix="${1:-tmp}"
    
    if deps_has "mktemp"; then
        "${_TOOL_PATH[mktemp]}" -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
    else
        # Fallback using $$ and RANDOM
        local path="${TMPDIR:-/tmp}/${prefix}.${$}.${RANDOM}"
        mkdir -p "$path" && echo "$path"
    fi
}

# -----------------------------------------------------------------------------
# Module readiness check
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Check if fs module is ready to use
# Usage: fs_ready -> returns 0 if ready, 1 if not
fs_ready() {
    [[ "$_FS_READY" == "1" ]]
}

# @@PUBLIC_API@@
# Get fs module error message (if not ready)
# Usage: fs_error -> prints error message
fs_error() {
    echo "$_FS_ERROR"
}
