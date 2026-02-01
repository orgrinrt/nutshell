#!/usr/bin/env bash
# =============================================================================
# nutshell/core/deps.sh - Dependency checking and variant detection
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer -1 (Foundation): Depends only on os.sh
#
# Nutshell requires certain external tools that are typically pre-installed
# on Unix systems but may vary in their implementation (BSD vs GNU).
# This module detects what's available and provides abstraction.
#
# Required tools:
#   - sed      (stream editor)
#   - awk      (text processing)
#   - grep     (pattern matching)
#   - stat     (file information)
#   - mktemp   (temporary files)
#   - find     (file discovery)
#   - sort     (sorting)
#   - wc       (word/line count)
#   - tr       (character translation)
#   - head     (first lines)
#   - tail     (last lines)
#   - dirname  (directory portion of path)
#   - basename (filename portion of path)
#   - uname    (system information)
#
# Environment variables for custom paths:
#   NUTSHELL_SED      - Path to sed
#   NUTSHELL_AWK      - Path to awk
#   NUTSHELL_GREP     - Path to grep
#   NUTSHELL_STAT     - Path to stat
#   NUTSHELL_MKTEMP   - Path to mktemp
#   NUTSHELL_FIND     - Path to find
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_DEPS_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_DEPS_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

_NUTSHELL_DEPS_DIR="${BASH_SOURCE[0]%/*}"
source "${_NUTSHELL_DEPS_DIR}/os.sh"

# -----------------------------------------------------------------------------
# Tool paths (resolved once at load time)
# -----------------------------------------------------------------------------

# These can be overridden via environment variables
NUTSHELL_SED="${NUTSHELL_SED:-}"
NUTSHELL_AWK="${NUTSHELL_AWK:-}"
NUTSHELL_GREP="${NUTSHELL_GREP:-}"
NUTSHELL_STAT="${NUTSHELL_STAT:-}"
NUTSHELL_MKTEMP="${NUTSHELL_MKTEMP:-}"
NUTSHELL_FIND="${NUTSHELL_FIND:-}"

# Detected variants (gnu/bsd/unknown)
_NUTSHELL_SED_VARIANT=""
_NUTSHELL_AWK_VARIANT=""
_NUTSHELL_GREP_VARIANT=""
_NUTSHELL_STAT_VARIANT=""

# -----------------------------------------------------------------------------
# Internal: Tool detection
# -----------------------------------------------------------------------------

# Find a command, preferring custom path, then common locations
_deps_find_cmd() {
    local name="$1"
    local custom_var="$2"
    local custom_path="${!custom_var:-}"
    
    # Custom path takes precedence
    if [[ -n "$custom_path" ]] && [[ -x "$custom_path" ]]; then
        echo "$custom_path"
        return 0
    fi
    
    # Try command -v (standard lookup)
    local found
    if found="$(command -v "$name" 2>/dev/null)"; then
        echo "$found"
        return 0
    fi
    
    # Try common locations
    local locations=(
        "/usr/bin/$name"
        "/bin/$name"
        "/usr/local/bin/$name"
        "/opt/homebrew/bin/$name"
    )
    
    for loc in "${locations[@]}"; do
        if [[ -x "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done
    
    return 1
}

# Detect sed variant (gnu/bsd)
_deps_detect_sed_variant() {
    local sed_cmd="$1"
    
    # GNU sed has --version, BSD sed does not
    if "$sed_cmd" --version 2>/dev/null | grep -q "GNU"; then
        echo "gnu"
    elif "$sed_cmd" --version 2>&1 | grep -q "illegal option"; then
        echo "bsd"
    else
        echo "unknown"
    fi
}

# Detect awk variant (gawk/mawk/nawk/bsd)
_deps_detect_awk_variant() {
    local awk_cmd="$1"
    
    if "$awk_cmd" --version 2>/dev/null | grep -qi "GNU Awk"; then
        echo "gawk"
    elif "$awk_cmd" -W version 2>/dev/null | grep -qi "mawk"; then
        echo "mawk"
    elif [[ "$(basename "$awk_cmd")" == "nawk" ]]; then
        echo "nawk"
    else
        echo "bsd"
    fi
}

# Detect grep variant (gnu/bsd)
_deps_detect_grep_variant() {
    local grep_cmd="$1"
    
    if "$grep_cmd" --version 2>/dev/null | grep -q "GNU"; then
        echo "gnu"
    else
        echo "bsd"
    fi
}

# Detect stat variant (gnu/bsd)
_deps_detect_stat_variant() {
    local stat_cmd="$1"
    
    # GNU stat uses -c for format, BSD uses -f
    if "$stat_cmd" --version 2>/dev/null | grep -q "GNU"; then
        echo "gnu"
    elif "$stat_cmd" -f%z / 2>/dev/null >/dev/null; then
        echo "bsd"
    else
        echo "unknown"
    fi
}

# -----------------------------------------------------------------------------
# Initialization
# -----------------------------------------------------------------------------

_deps_init() {
    # Find tools
    NUTSHELL_SED="$(_deps_find_cmd "sed" "NUTSHELL_SED")" || NUTSHELL_SED=""
    NUTSHELL_AWK="$(_deps_find_cmd "awk" "NUTSHELL_AWK")" || NUTSHELL_AWK=""
    NUTSHELL_GREP="$(_deps_find_cmd "grep" "NUTSHELL_GREP")" || NUTSHELL_GREP=""
    NUTSHELL_STAT="$(_deps_find_cmd "stat" "NUTSHELL_STAT")" || NUTSHELL_STAT=""
    NUTSHELL_MKTEMP="$(_deps_find_cmd "mktemp" "NUTSHELL_MKTEMP")" || NUTSHELL_MKTEMP=""
    NUTSHELL_FIND="$(_deps_find_cmd "find" "NUTSHELL_FIND")" || NUTSHELL_FIND=""
    
    # Detect variants
    [[ -n "$NUTSHELL_SED" ]] && _NUTSHELL_SED_VARIANT="$(_deps_detect_sed_variant "$NUTSHELL_SED")"
    [[ -n "$NUTSHELL_AWK" ]] && _NUTSHELL_AWK_VARIANT="$(_deps_detect_awk_variant "$NUTSHELL_AWK")"
    [[ -n "$NUTSHELL_GREP" ]] && _NUTSHELL_GREP_VARIANT="$(_deps_detect_grep_variant "$NUTSHELL_GREP")"
    [[ -n "$NUTSHELL_STAT" ]] && _NUTSHELL_STAT_VARIANT="$(_deps_detect_stat_variant "$NUTSHELL_STAT")"
}

# Run initialization
_deps_init

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Check if a required tool is available
# Usage: deps_has "toolname" -> returns 0 (true) or 1 (false)
deps_has() {
    local tool="$1"
    
    case "$tool" in
        sed)    [[ -n "$NUTSHELL_SED" ]] ;;
        awk)    [[ -n "$NUTSHELL_AWK" ]] ;;
        grep)   [[ -n "$NUTSHELL_GREP" ]] ;;
        stat)   [[ -n "$NUTSHELL_STAT" ]] ;;
        mktemp) [[ -n "$NUTSHELL_MKTEMP" ]] ;;
        find)   [[ -n "$NUTSHELL_FIND" ]] ;;
        *)      command -v "$tool" &>/dev/null ;;
    esac
}

# @@PUBLIC_API@@
# Get the path to a tool
# Usage: deps_path "toolname" -> prints path or returns 1
deps_path() {
    local tool="$1"
    
    case "$tool" in
        sed)    [[ -n "$NUTSHELL_SED" ]] && echo "$NUTSHELL_SED" ;;
        awk)    [[ -n "$NUTSHELL_AWK" ]] && echo "$NUTSHELL_AWK" ;;
        grep)   [[ -n "$NUTSHELL_GREP" ]] && echo "$NUTSHELL_GREP" ;;
        stat)   [[ -n "$NUTSHELL_STAT" ]] && echo "$NUTSHELL_STAT" ;;
        mktemp) [[ -n "$NUTSHELL_MKTEMP" ]] && echo "$NUTSHELL_MKTEMP" ;;
        find)   [[ -n "$NUTSHELL_FIND" ]] && echo "$NUTSHELL_FIND" ;;
        *)      command -v "$tool" 2>/dev/null ;;
    esac
}

# @@PUBLIC_API@@
# Get the variant of a tool (gnu/bsd/gawk/mawk/etc)
# Usage: deps_variant "toolname" -> prints variant or "unknown"
deps_variant() {
    local tool="$1"
    
    case "$tool" in
        sed)  echo "${_NUTSHELL_SED_VARIANT:-unknown}" ;;
        awk)  echo "${_NUTSHELL_AWK_VARIANT:-unknown}" ;;
        grep) echo "${_NUTSHELL_GREP_VARIANT:-unknown}" ;;
        stat) echo "${_NUTSHELL_STAT_VARIANT:-unknown}" ;;
        *)    echo "unknown" ;;
    esac
}

# @@PUBLIC_API@@
# Check if a tool is the GNU variant
# Usage: deps_is_gnu "toolname" -> returns 0 (true) or 1 (false)
deps_is_gnu() {
    local tool="$1"
    local variant
    variant="$(deps_variant "$tool")"
    [[ "$variant" == "gnu" ]] || [[ "$variant" == "gawk" ]]
}

# @@PUBLIC_API@@
# Check if a tool is the BSD variant
# Usage: deps_is_bsd "toolname" -> returns 0 (true) or 1 (false)
deps_is_bsd() {
    local tool="$1"
    local variant
    variant="$(deps_variant "$tool")"
    [[ "$variant" == "bsd" ]]
}

# @@PUBLIC_API@@
# Check all required dependencies and report missing ones
# Usage: deps_check_all -> returns 0 if all present, 1 if any missing
deps_check_all() {
    local missing=()
    local tools=("sed" "awk" "grep" "stat" "mktemp" "find" "sort" "wc" "tr" "head" "tail" "dirname" "basename" "uname")
    
    for tool in "${tools[@]}"; do
        if ! deps_has "$tool"; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing required tools: ${missing[*]}" >&2
        return 1
    fi
    
    return 0
}

# @@PUBLIC_API@@
# Print dependency information for debugging
# Usage: deps_info -> prints tool paths and variants
deps_info() {
    echo "nutshell dependency information:"
    echo "================================"
    echo ""
    echo "Tool paths:"
    echo "  sed:    ${NUTSHELL_SED:-NOT FOUND}"
    echo "  awk:    ${NUTSHELL_AWK:-NOT FOUND}"
    echo "  grep:   ${NUTSHELL_GREP:-NOT FOUND}"
    echo "  stat:   ${NUTSHELL_STAT:-NOT FOUND}"
    echo "  mktemp: ${NUTSHELL_MKTEMP:-NOT FOUND}"
    echo "  find:   ${NUTSHELL_FIND:-NOT FOUND}"
    echo ""
    echo "Variants:"
    echo "  sed:    ${_NUTSHELL_SED_VARIANT:-unknown}"
    echo "  awk:    ${_NUTSHELL_AWK_VARIANT:-unknown}"
    echo "  grep:   ${_NUTSHELL_GREP_VARIANT:-unknown}"
    echo "  stat:   ${_NUTSHELL_STAT_VARIANT:-unknown}"
    echo ""
    echo "Operating system: $(os_name)"
    echo "Architecture:     $(os_arch)"
}

# @@PUBLIC_API@@
# Require a tool to be present, exit if not
# Usage: deps_require "toolname" ["error message"]
deps_require() {
    local tool="$1"
    local msg="${2:-Required tool '$tool' not found}"
    
    if ! deps_has "$tool"; then
        echo "[FATAL] $msg" >&2
        exit 1
    fi
}

# @@PUBLIC_API@@
# Require all standard tools to be present
# Usage: deps_require_all -> exits if any missing
deps_require_all() {
    if ! deps_check_all; then
        echo "[FATAL] Cannot continue without required tools." >&2
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Portable wrappers for tools with BSD/GNU differences
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Portable sed in-place edit (handles BSD vs GNU difference)
# Usage: deps_sed_inplace "pattern" "file"
deps_sed_inplace() {
    local pattern="$1"
    local file="$2"
    
    if deps_is_gnu "sed"; then
        "$NUTSHELL_SED" -i "$pattern" "$file"
    else
        # BSD sed requires an argument after -i (backup extension)
        # Empty string means no backup
        "$NUTSHELL_SED" -i '' "$pattern" "$file"
    fi
}

# @@PUBLIC_API@@
# Portable stat for file size in bytes
# Usage: deps_stat_size "file" -> prints size in bytes
deps_stat_size() {
    local file="$1"
    
    if deps_is_gnu "stat"; then
        "$NUTSHELL_STAT" -c%s "$file"
    else
        "$NUTSHELL_STAT" -f%z "$file"
    fi
}

# @@PUBLIC_API@@
# Portable stat for modification time (epoch seconds)
# Usage: deps_stat_mtime "file" -> prints mtime as epoch seconds
deps_stat_mtime() {
    local file="$1"
    
    if deps_is_gnu "stat"; then
        "$NUTSHELL_STAT" -c%Y "$file"
    else
        "$NUTSHELL_STAT" -f%m "$file"
    fi
}
