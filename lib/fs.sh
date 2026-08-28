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

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded: under a POSIX shell `nut_once` is not found, the `|| return
# 0` returns from the whole file, and the module then defines nothing while
# reporting success.
[ -n "${_NUTSHELL_FS_SH:-}" ] && return 0
_NUTSHELL_FS_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

# Declared, not sourced by path. A hand-rolled `source` loads the module and
# hides it from the module-contract check, which reads `use` lines, so the
# dependency was real and unrecorded at once.
use deps

# The two variables that were here computed a path to the implementation
# directory from `BASH_SOURCE`, and nothing read the second. They are from
# before the resolver, when an implementation was sourced by path; it is loaded
# by name now, which is what makes the module contract checkable at all.

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

#[pub]
#[allow(trivial_wrapper)]
# Check if path exists (file or directory)
# Usage: fs_exists "path" -> returns 0 (true) or 1 (false)
fs_exists() {
    [ -e "${1:-}" ]
}

#[pub]
#[allow(trivial_wrapper)]
# Check if path is a regular file
# Usage: fs_is_file "path" -> returns 0 (true) or 1 (false)
fs_is_file() {
    [ -f "${1:-}" ]
}

#[pub]
#[allow(trivial_wrapper)]
# Check if path is a directory
# Usage: fs_is_dir "path" -> returns 0 (true) or 1 (false)
fs_is_dir() {
    [ -d "${1:-}" ]
}

#[pub]
#[allow(trivial_wrapper)]
# Check if path is a symbolic link
# Usage: fs_is_link "path" -> returns 0 (true) or 1 (false)
fs_is_link() {
    [ -L "${1:-}" ]
}

#[pub]
#[allow(trivial_wrapper)]
# Check if file is readable
# Usage: fs_is_readable "path" -> returns 0 (true) or 1 (false)
fs_is_readable() {
    [ -r "${1:-}" ]
}

#[pub]
#[allow(trivial_wrapper)]
# Check if file is writable
# Usage: fs_is_writable "path" -> returns 0 (true) or 1 (false)
fs_is_writable() {
    [ -w "${1:-}" ]
}

#[pub]
#[allow(trivial_wrapper)]
# Check if file is executable
# Usage: fs_is_executable "path" -> returns 0 (true) or 1 (false)
fs_is_executable() {
    [ -x "${1:-}" ]
}

#[pub]
#[allow(trivial_wrapper)]
# Check if file is non-empty
# Usage: fs_is_nonempty "path" -> returns 0 (true) or 1 (false)
fs_is_nonempty() {
    [ -s "${1:-}" ]
}

# -----------------------------------------------------------------------------
# Directory operations (standard tools)
# -----------------------------------------------------------------------------

#[pub]
# Create directory (and parents) if it doesn't exist
# Usage: fs_mkdir "/path/to/dir" -> returns 0 on success
fs_mkdir() {
    local path="${1:-}"
    [ -z "$path" ] && return 1
    [ -d "$path" ] && return 0
    mkdir -p "$path"
}

# -----------------------------------------------------------------------------
# File operations (standard tools)
# -----------------------------------------------------------------------------

#[pub]
# Remove file or directory (safe - doesn't fail if missing)
# Usage: fs_rm "/path/to/remove" -> returns 0 on success
fs_rm() {
    local path="${1:-}"
    [ -z "$path" ] && return 1
    [ ! -e "$path" ] && return 0
    rm -rf "$path"
}

#[pub]
# Copy file or directory
# Usage: fs_cp "source" "dest" -> returns 0 on success
fs_cp() {
    local src="${1:-}"
    local dst="${2:-}"
    { [ -z "$src" ] || [ -z "$dst" ]; } && return 1
    [ ! -e "$src" ] && return 1
    cp -r "$src" "$dst"
}

#[pub]
# Move file or directory
# Usage: fs_mv "source" "dest" -> returns 0 on success
fs_mv() {
    local src="${1:-}"
    local dst="${2:-}"
    { [ -z "$src" ] || [ -z "$dst" ]; } && return 1
    [ ! -e "$src" ] && return 1
    mv "$src" "$dst"
}

# -----------------------------------------------------------------------------
# Path manipulation (pure bash + standard tools)
# -----------------------------------------------------------------------------

#[pub]
# Get absolute path (resolves symlinks)
# Usage: fs_realpath "relative/path" -> "/absolute/path"
fs_realpath() {
    local path="${1:-}"
    [ -z "$path" ] && return 1
    
    if [ -d "$path" ]; then
        (cd "$path" && pwd -P)
    elif [ -f "$path" ]; then
        local dir base
        dir="$(cd "$(dirname "$path")" && pwd -P)"
        base="$(basename "$path")"
        echo "${dir}/${base}"
    else
        # Path doesn't exist - resolve what we can
        local dir base
        dir="$(dirname "$path")"
        base="$(basename "$path")"
        if [ -d "$dir" ]; then
            echo "$(cd "$dir" && pwd -P)/${base}"
        else
            echo "$path"
        fi
    fi
}

#[pub]
# Get directory portion of path
# Usage: fs_dirname "/path/to/file" -> "/path/to"
fs_dirname() {
    local path="${1:-}"
    [ -z "$path" ] && return 1
    dirname "$path"
}

#[pub]
# Get filename portion of path
# Usage: fs_basename "/path/to/file.txt" -> "file.txt"
fs_basename() {
    local path="${1:-}"
    [ -z "$path" ] && return 1
    basename "$path"
}

#[pub]
# Get file extension
# Usage: fs_extension "file.txt" -> "txt"
fs_extension() {
    local path="${1:-}"
    local base
    base="$(basename "$path")"
    
    # No extension if no dot or starts with dot
    case "$base" in
        *.*) ;;
        *) return 0 ;;
    esac
    # A name that is only a leading dot and one word is all extension and no
    # stem, which is a dotfile rather than a file with a suffix.
    case "$base" in
        .*) case "${base#.}" in *.*) ;; *) return 0 ;; esac ;;
    esac
    
    echo "${base##*.}"
}

#[pub]
# Get filename without extension
# Usage: fs_basename_no_ext "file.txt" -> "file"
fs_basename_no_ext() {
    local path="${1:-}"
    local base
    base="$(basename "$path")"
    
    # No extension to remove
    case "$base" in
        *.*) ;;
        *) echo "$base"; return 0 ;;
    esac
    case "$base" in
        .*) case "${base#.}" in *.*) ;; *) echo "$base"; return 0 ;; esac ;;
    esac
    
    echo "${base%.*}"
}

# -----------------------------------------------------------------------------
# File information - LAZY INIT STUBS
# These stubs select and source the best implementation on first call
# -----------------------------------------------------------------------------

#[pub]
# Get file size in bytes
# Usage: fs_size "/path/to/file" -> "12345"
fs_size() {
    nut_lazy_guard fs_size || return 1
    local _NUT_LAZY_fs_size=1
    # First call: decide which implementation to use
    local impl=""
    
    if deps_has "stat"; then
        local variant="${_TOOL_VARIANT_stat:-unknown}"
        case "$variant" in
            gnu)     impl="stat_gnu" ;;
            bsd)     impl="stat_bsd" ;;
            *)
                # Unknown variant; try perl if available
                if deps_has "perl"; then
                    impl="perl_stat"
                else
                    # Guess based on OS
                    case "$(uname -s)" in
                        Darwin*) impl="stat_bsd" ;;
                        *)       impl="stat_gnu" ;;
                    esac
                fi
                ;;
        esac
    elif deps_has "perl"; then
        impl="perl_stat"
    fi
    
    # Written out rather than assembled from `$impl`.
    #
    # Named, not sourced by a path: the resolver knows where the module is,
    # loads it once however many callers arrive, and the declaration covers
    # it. That part was already right.
    #
    # What was not: `nut_reload "super::fs::impl::${impl}"` builds the name at
    # run time, so nothing reading this file can tell which modules it can
    # reach. Every other dispatch in the library is literal, thirteen of them
    # in `text.sh` alone, and these two were the only ones that were not. A
    # pass that drops what nothing calls would drop two of these three and
    # fail at first call on whichever machine has the other `stat`.
    #
    # The set is closed and has three members, so writing them out costs four
    # lines and makes the whole library statically readable.
    case "$impl" in
        stat_gnu)  nut_reload super::fs::impl::stat_gnu ;;
        stat_bsd)  nut_reload super::fs::impl::stat_bsd ;;
        perl_stat) nut_reload super::fs::impl::perl_stat ;;
    esac

    if [ -z "$impl" ]; then
        fs_size() {
            echo "[ERROR] fs_size: no stat tool available" >&2
            return 1
        }
    fi
    
    # Call the now-replaced function
    fs_size "$@"
}

#[pub]
# Get file modification time (epoch seconds)
# Usage: fs_mtime "/path/to/file" -> "1234567890"
fs_mtime() {
    nut_lazy_guard fs_mtime || return 1
    local _NUT_LAZY_fs_mtime=1
    # First call: decide which implementation to use
    local impl=""
    
    if deps_has "stat"; then
        local variant="${_TOOL_VARIANT_stat:-unknown}"
        case "$variant" in
            gnu)     impl="stat_gnu" ;;
            bsd)     impl="stat_bsd" ;;
            *)
                if deps_has "perl"; then
                    impl="perl_stat"
                else
                    case "$(uname -s)" in
                        Darwin*) impl="stat_bsd" ;;
                        *)       impl="stat_gnu" ;;
                    esac
                fi
                ;;
        esac
    elif deps_has "perl"; then
        impl="perl_stat"
    fi
    
    # Written out rather than assembled from `$impl`.
    #
    # Named, not sourced by a path: the resolver knows where the module is,
    # loads it once however many callers arrive, and the declaration covers
    # it. That part was already right.
    #
    # What was not: `nut_reload "super::fs::impl::${impl}"` builds the name at
    # run time, so nothing reading this file can tell which modules it can
    # reach. Every other dispatch in the library is literal, thirteen of them
    # in `text.sh` alone, and these two were the only ones that were not. A
    # pass that drops what nothing calls would drop two of these three and
    # fail at first call on whichever machine has the other `stat`.
    #
    # The set is closed and has three members, so writing them out costs four
    # lines and makes the whole library statically readable.
    case "$impl" in
        stat_gnu)  nut_reload super::fs::impl::stat_gnu ;;
        stat_bsd)  nut_reload super::fs::impl::stat_bsd ;;
        perl_stat) nut_reload super::fs::impl::perl_stat ;;
    esac

    if [ -z "$impl" ]; then
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

#[pub]
# Create a temporary file and print its path
# Usage: fs_temp_file [prefix] -> "/tmp/prefix.XXXXXX"
fs_temp_file() {
    local prefix="${1:-tmp}"
    
    if deps_has "mktemp"; then
        "${_TOOL_PATH_mktemp}" "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
    else
        # Fallback using $$ and RANDOM
        local path="${TMPDIR:-/tmp}/${prefix}.${$}.${RANDOM}"
        touch "$path" && echo "$path"
    fi
}

#[pub]
# Create a temporary directory and print its path
# Usage: fs_temp_dir [prefix] -> "/tmp/prefix.XXXXXX"
fs_temp_dir() {
    local prefix="${1:-tmp}"
    
    if deps_has "mktemp"; then
        "${_TOOL_PATH_mktemp}" -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
    else
        # Fallback using $$ and RANDOM
        local path="${TMPDIR:-/tmp}/${prefix}.${$}.${RANDOM}"
        mkdir -p "$path" && echo "$path"
    fi
}

# -----------------------------------------------------------------------------
# Module readiness check
# -----------------------------------------------------------------------------

#[pub]
# Check if fs module is ready to use
# Usage: fs_ready -> returns 0 if ready, 1 if not
fs_ready() {
    [ "$_FS_READY" = "1" ]
}

#[pub]
# Get fs module error message (if not ready)
# Usage: fs_error -> prints error message
fs_error() {
    echo "$_FS_ERROR"
}
