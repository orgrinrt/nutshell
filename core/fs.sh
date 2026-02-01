#!/usr/bin/env bash
# =============================================================================
# nutshell/core/fs.sh - Filesystem primitives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): No dependencies on other modules
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_FS_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_FS_SH=1

# -----------------------------------------------------------------------------
# Existence checks
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
# Directory operations
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
# File operations
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
# Path manipulation
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
# File information
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Get file size in bytes
# Usage: fs_size "/path/to/file" -> "12345"
fs_size() {
    local path="${1:-}"
    [[ ! -f "$path" ]] && return 1
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
        stat -f%z "$path"
    else
        stat -c%s "$path"
    fi
}

# @@PUBLIC_API@@
# Get file modification time (epoch seconds)
# Usage: fs_mtime "/path/to/file" -> "1234567890"
fs_mtime() {
    local path="${1:-}"
    [[ ! -e "$path" ]] && return 1
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
        stat -f%m "$path"
    else
        stat -c%Y "$path"
    fi
}

# -----------------------------------------------------------------------------
# Temporary files
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Create a temporary file and print its path
# Usage: fs_temp_file [prefix] -> "/tmp/prefix.XXXXXX"
fs_temp_file() {
    local prefix="${1:-tmp}"
    mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}

# @@PUBLIC_API@@
# Create a temporary directory and print its path
# Usage: fs_temp_dir [prefix] -> "/tmp/prefix.XXXXXX"
fs_temp_dir() {
    local prefix="${1:-tmp}"
    mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX"
}
