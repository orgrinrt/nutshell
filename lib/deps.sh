#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/deps.sh - Environment detection and tool availability
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# @@ALLOW_LOC_450@@
# Layer -1 (Foundation): Depends only on os.sh
#
# This module detects what external tools are available and collects
# information about them (paths, variants, capabilities). It does NOT
# decide which tool is "best" for any operation; that's the job of
# the module that actually uses the tool.
#
# Detection runs once when this file is sourced. Results are cached
# in readonly variables for fast access.
#
# Tools detected:
#   sed, awk, grep, perl, stat, mktemp, find, sort, wc, tr,
#   head, tail, dirname, basename, uname, cut, tee, xargs
#
# Configuration:
#   Tool paths can be overridden in nut.toml under [deps.paths]:
#     [deps.paths]
#     sed = "/opt/gnu/bin/sed"
#     awk = "/usr/local/bin/gawk"
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_DEPS_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_DEPS_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

_NUTSHELL_DEPS_DIR="${BASH_SOURCE[0]%/*}"
# Handle case when sourced from same directory (BASH_SOURCE[0] has no path component)
[[ "$_NUTSHELL_DEPS_DIR" == "${BASH_SOURCE[0]}" ]] && _NUTSHELL_DEPS_DIR="."
source "${_NUTSHELL_DEPS_DIR}/os.sh"

# -----------------------------------------------------------------------------
# Configuration file location
# -----------------------------------------------------------------------------

# Find nut.toml - check current dir, then repo root, then nutshell dir
_deps_find_config() {
    local check_paths=(
        "${PWD}/nut.toml"
        "${_NUTSHELL_DEPS_DIR}/../nut.toml"
    )
    
    for path in "${check_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# Simple TOML value extraction (no toml.sh dependency to avoid circular deps)
# Only handles simple key = "value" or key = value cases
_deps_toml_get() {
    local file="$1"
    local section="$2"
    local key="$3"
    
    [[ ! -f "$file" ]] && return 1
    
    local in_section=0
    local current_section=""
    local line
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Section header
        if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            if [[ "$current_section" == "$section" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi
        
        # Skip if not in the right section
        [[ $in_section -eq 0 ]] && continue
        
        # Key = value
        if [[ "$line" =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            local k="${BASH_REMATCH[1]}"
            local v="${BASH_REMATCH[2]}"
            # Trim whitespace
            k="${k#"${k%%[![:space:]]*}"}"
            k="${k%"${k##*[![:space:]]}"}"
            v="${v#"${v%%[![:space:]]*}"}"
            v="${v%"${v##*[![:space:]]}"}"
            # Remove quotes
            v="${v#\"}"
            v="${v%\"}"
            v="${v#\'}"
            v="${v%\'}"
            
            if [[ "$k" == "$key" ]]; then
                echo "$v"
                return 0
            fi
        fi
    done < "$file"
    
    return 1
}

# -----------------------------------------------------------------------------
# Global state - populated by _deps_init
# -----------------------------------------------------------------------------

# Space-separated list of available tools
# Use -g for global scope when sourced from within a function (like use())
declare -g _TOOLS_AVAILABLE=""

# Associative array: tool name -> path
declare -gA _TOOL_PATH=() 2>/dev/null || declare -A _TOOL_PATH=()

# Associative array: tool name -> variant (gnu/bsd/gawk/mawk/nawk/unknown)
declare -gA _TOOL_VARIANT=() 2>/dev/null || declare -A _TOOL_VARIANT=()

# Associative array: capability -> 1 (present) or 0 (absent)
# Capabilities are named as tool_capability, e.g., sed_inplace, grep_pcre
declare -gA _TOOL_CAN=() 2>/dev/null || declare -A _TOOL_CAN=()

# -----------------------------------------------------------------------------
# Internal: Path resolution
# -----------------------------------------------------------------------------

# Find tool path using resolution order:
# 1. User config (nut.toml [deps.paths])
# 2. which (if available)
# 3. Common locations, verified for executability
_deps_find_tool() {
    local tool="$1"
    local config_file="$2"
    
    # 1. Check user config first
    if [[ -n "$config_file" ]]; then
        local user_path
        user_path="$(_deps_toml_get "$config_file" "deps.paths" "$tool")"
        if [[ -n "$user_path" ]] && [[ -x "$user_path" ]]; then
            echo "$user_path"
            return 0
        fi
    fi
    
    # 2. Try which if available (using command -v to check for which itself)
    if command -v which &>/dev/null; then
        local found
        found="$(which "$tool" 2>/dev/null)"
        if [[ -n "$found" ]] && [[ -x "$found" ]]; then
            echo "$found"
            return 0
        fi
    fi
    
    # 3. Check common locations
    local locations=(
        "/usr/bin/${tool}"
        "/bin/${tool}"
        "/usr/local/bin/${tool}"
        "/opt/homebrew/bin/${tool}"
    )
    
    for loc in "${locations[@]}"; do
        if [[ -x "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done
    
    # Not found
    return 1
}

# -----------------------------------------------------------------------------
# Internal: Variant detection
# -----------------------------------------------------------------------------

_deps_detect_sed_variant() {
    local cmd="$1"
    
    # GNU sed has --version
    if "$cmd" --version 2>/dev/null | grep -q "GNU"; then
        echo "gnu"
        return
    fi
    
    # BSD sed errors on --version
    if "$cmd" --version 2>&1 | grep -qE "(illegal|invalid) option"; then
        echo "bsd"
        return
    fi
    
    echo "unknown"
}

_deps_detect_awk_variant() {
    local cmd="$1"
    
    # GNU awk (gawk)
    if "$cmd" --version 2>/dev/null | grep -qi "GNU Awk"; then
        echo "gawk"
        return
    fi
    
    # mawk
    if "$cmd" -W version 2>/dev/null | grep -qi "mawk"; then
        echo "mawk"
        return
    fi
    
    # nawk (check binary name as fallback)
    if [[ "$(basename "$cmd")" == "nawk" ]]; then
        echo "nawk"
        return
    fi
    
    # Assume BSD/POSIX awk
    echo "bsd"
}

_deps_detect_grep_variant() {
    local cmd="$1"
    
    if "$cmd" --version 2>/dev/null | grep -q "GNU"; then
        echo "gnu"
        return
    fi
    
    echo "bsd"
}

_deps_detect_stat_variant() {
    local cmd="$1"
    
    # GNU stat has --version
    if "$cmd" --version 2>/dev/null | grep -q "GNU"; then
        echo "gnu"
        return
    fi
    
    # BSD stat uses -f for format
    if "$cmd" -f%z / 2>/dev/null >/dev/null; then
        echo "bsd"
        return
    fi
    
    echo "unknown"
}

_deps_detect_find_variant() {
    local cmd="$1"
    
    if "$cmd" --version 2>/dev/null | grep -q "GNU"; then
        echo "gnu"
        return
    fi
    
    echo "bsd"
}

# -----------------------------------------------------------------------------
# Internal: Capability detection
# -----------------------------------------------------------------------------

_deps_detect_capabilities() {
    # sed capabilities
    if [[ -n "${_TOOL_PATH[sed]:-}" ]]; then
        local sed_cmd="${_TOOL_PATH[sed]}"
        local variant="${_TOOL_VARIANT[sed]:-unknown}"
        
        # In-place editing
        # GNU: sed -i 'cmd' file
        # BSD: sed -i '' 'cmd' file
        _TOOL_CAN[sed_inplace]=1
        
        # Extended regex (-E)
        # Both GNU and BSD support -E now
        if "$sed_cmd" -E 's/a/b/' /dev/null 2>/dev/null; then
            _TOOL_CAN[sed_extended]=1
        else
            _TOOL_CAN[sed_extended]=0
        fi
        
        # GNU-specific -r (same as -E but older)
        if [[ "$variant" == "gnu" ]]; then
            _TOOL_CAN[sed_regex_r]=1
        else
            _TOOL_CAN[sed_regex_r]=0
        fi
    fi
    
    # grep capabilities
    if [[ -n "${_TOOL_PATH[grep]:-}" ]]; then
        local grep_cmd="${_TOOL_PATH[grep]}"
        
        # Extended regex (-E)
        _TOOL_CAN[grep_extended]=1
        
        # PCRE (-P) - mainly GNU grep
        if echo "test" | "$grep_cmd" -P "t.st" &>/dev/null; then
            _TOOL_CAN[grep_pcre]=1
        else
            _TOOL_CAN[grep_pcre]=0
        fi
        
        # --include/--exclude for recursive searches
        if "$grep_cmd" --help 2>&1 | grep -q -- '--include'; then
            _TOOL_CAN[grep_include]=1
        else
            _TOOL_CAN[grep_include]=0
        fi
        
        # -o (only matching)
        if echo "test" | "$grep_cmd" -o "es" &>/dev/null; then
            _TOOL_CAN[grep_only_matching]=1
        else
            _TOOL_CAN[grep_only_matching]=0
        fi
    fi
    
    # awk capabilities
    if [[ -n "${_TOOL_PATH[awk]:-}" ]]; then
        local awk_cmd="${_TOOL_PATH[awk]}"
        local variant="${_TOOL_VARIANT[awk]:-unknown}"
        
        # Regex matching (all awks have this)
        _TOOL_CAN[awk_regex]=1
        
        # gawk-specific features
        if [[ "$variant" == "gawk" ]]; then
            _TOOL_CAN[awk_nextfile]=1
            _TOOL_CAN[awk_strftime]=1
            _TOOL_CAN[awk_gensub]=1
        else
            _TOOL_CAN[awk_nextfile]=0
            _TOOL_CAN[awk_strftime]=0
            _TOOL_CAN[awk_gensub]=0
        fi
    fi
    
    # stat capabilities
    if [[ -n "${_TOOL_PATH[stat]:-}" ]]; then
        local stat_cmd="${_TOOL_PATH[stat]}"
        local variant="${_TOOL_VARIANT[stat]:-unknown}"
        
        # Format strings
        if [[ "$variant" == "gnu" ]] || [[ "$variant" == "bsd" ]]; then
            _TOOL_CAN[stat_format]=1
        else
            _TOOL_CAN[stat_format]=0
        fi
    fi
    
    # perl capabilities
    if [[ -n "${_TOOL_PATH[perl]:-}" ]]; then
        local perl_cmd="${_TOOL_PATH[perl]}"
        
        # Basic perl is always capable
        _TOOL_CAN[perl_regex]=1
        _TOOL_CAN[perl_inplace]=1
        
        # Check for common modules (optional)
        if "$perl_cmd" -MJSON -e '1' 2>/dev/null; then
            _TOOL_CAN[perl_json]=1
        else
            _TOOL_CAN[perl_json]=0
        fi
    fi
    
    # find capabilities
    if [[ -n "${_TOOL_PATH[find]:-}" ]]; then
        local find_cmd="${_TOOL_PATH[find]}"
        local variant="${_TOOL_VARIANT[find]:-unknown}"
        
        # -maxdepth (both have it now)
        _TOOL_CAN[find_maxdepth]=1
        
        # -printf (GNU only)
        if [[ "$variant" == "gnu" ]]; then
            _TOOL_CAN[find_printf]=1
        else
            _TOOL_CAN[find_printf]=0
        fi
    fi
}

# -----------------------------------------------------------------------------
# Initialization
# -----------------------------------------------------------------------------

_deps_init() {
    local config_file
    config_file="$(_deps_find_config)" || config_file=""
    
    # List of tools to detect
    local tools=(
        sed awk grep perl stat mktemp find sort wc tr
        head tail dirname basename uname cut tee xargs
    )
    
    local available=()
    local tool path variant
    
    for tool in "${tools[@]}"; do
        if path="$(_deps_find_tool "$tool" "$config_file")"; then
            _TOOL_PATH[$tool]="$path"
            available+=("$tool")
            
            # Detect variant for tools that have meaningful variants
            case "$tool" in
                sed)  _TOOL_VARIANT[$tool]="$(_deps_detect_sed_variant "$path")" ;;
                awk)  _TOOL_VARIANT[$tool]="$(_deps_detect_awk_variant "$path")" ;;
                grep) _TOOL_VARIANT[$tool]="$(_deps_detect_grep_variant "$path")" ;;
                stat) _TOOL_VARIANT[$tool]="$(_deps_detect_stat_variant "$path")" ;;
                find) _TOOL_VARIANT[$tool]="$(_deps_detect_find_variant "$path")" ;;
                *)    _TOOL_VARIANT[$tool]="standard" ;;
            esac
        fi
    done
    
    # Build space-separated available list
    _TOOLS_AVAILABLE="${available[*]}"
    
    # Detect capabilities based on what we found
    _deps_detect_capabilities
}

# Run initialization immediately
_deps_init

# Make arrays readonly after init (bash 4.2+)
# Note: associative arrays can't be made readonly in all bash versions,
# but we document that these should not be modified
declare -gr _TOOLS_AVAILABLE 2>/dev/null || declare -r _TOOLS_AVAILABLE

# -----------------------------------------------------------------------------
# Public API - Availability checks
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Check if a tool is available
# Usage: deps_has "sed" -> returns 0 (true) or 1 (false)
deps_has() {
    local tool="${1:-}"
    [[ -n "${_TOOL_PATH[$tool]:-}" ]]
}

# @@PUBLIC_API@@
# Check if multiple tools are all available
# Usage: deps_has_all "sed" "awk" "grep" -> returns 0 if all present
deps_has_all() {
    local tool
    for tool in "$@"; do
        [[ -z "${_TOOL_PATH[$tool]:-}" ]] && return 1
    done
    return 0
}

# @@PUBLIC_API@@
# Check if at least one of the tools is available
# Usage: deps_has_any "perl" "sed" -> returns 0 if any present
deps_has_any() {
    local tool
    for tool in "$@"; do
        [[ -n "${_TOOL_PATH[$tool]:-}" ]] && return 0
    done
    return 1
}

# @@PUBLIC_API@@
# Get the list of available tools (space-separated)
# Usage: deps_available -> "sed awk grep perl stat..."
deps_available() {
    echo "$_TOOLS_AVAILABLE"
}

# -----------------------------------------------------------------------------
# Public API - Path and variant access
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Get the path to a tool
# Usage: deps_path "sed" -> "/usr/bin/sed"
deps_path() {
    local tool="${1:-}"
    local path="${_TOOL_PATH[$tool]:-}"
    
    if [[ -n "$path" ]]; then
        echo "$path"
        return 0
    fi
    
    return 1
}

# @@PUBLIC_API@@
# Get the variant of a tool
# Usage: deps_variant "sed" -> "gnu" or "bsd"
deps_variant() {
    local tool="${1:-}"
    echo "${_TOOL_VARIANT[$tool]:-unknown}"
}

# @@PUBLIC_API@@
# Check if tool is GNU variant
# Usage: deps_is_gnu "sed" -> returns 0 or 1
deps_is_gnu() {
    local tool="${1:-}"
    local variant="${_TOOL_VARIANT[$tool]:-}"
    [[ "$variant" == "gnu" ]] || [[ "$variant" == "gawk" ]]
}

# @@PUBLIC_API@@
# Check if tool is BSD variant
# Usage: deps_is_bsd "sed" -> returns 0 or 1
deps_is_bsd() {
    local tool="${1:-}"
    local variant="${_TOOL_VARIANT[$tool]:-}"
    [[ "$variant" == "bsd" ]]
}

# -----------------------------------------------------------------------------
# Public API - Capability checks
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Check if a capability is available
# Usage: deps_can "grep_pcre" -> returns 0 or 1
deps_can() {
    local cap="${1:-}"
    [[ "${_TOOL_CAN[$cap]:-0}" == "1" ]]
}

# @@PUBLIC_API@@
# Get capability value (1 or 0)
# Usage: deps_cap "grep_pcre" -> "1" or "0"
deps_cap() {
    local cap="${1:-}"
    echo "${_TOOL_CAN[$cap]:-0}"
}

# @@PUBLIC_API@@
# List all capabilities (one per line: cap=value)
# Usage: deps_caps -> "sed_inplace=1\ngrep_pcre=1\n..."
deps_caps() {
    local cap
    for cap in "${!_TOOL_CAN[@]}"; do
        echo "${cap}=${_TOOL_CAN[$cap]}"
    done | sort
}

# -----------------------------------------------------------------------------
# Public API - Requirement enforcement
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Require a tool to be present; exit if not
# Usage: deps_require "sed" ["Custom error message"]
deps_require() {
    local tool="${1:-}"
    local msg="${2:-Required tool '$tool' not found}"
    
    if ! deps_has "$tool"; then
        echo "[FATAL] $msg" >&2
        exit 1
    fi
}

# @@PUBLIC_API@@
# Require multiple tools; exit if any missing
# Usage: deps_require_all "sed" "awk" "grep"
deps_require_all() {
    local missing=()
    local tool
    
    for tool in "$@"; do
        deps_has "$tool" || missing+=("$tool")
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[FATAL] Required tools not found: ${missing[*]}" >&2
        exit 1
    fi
}

# @@PUBLIC_API@@
# Require a capability; exit if not available
# Usage: deps_require_cap "grep_pcre" ["Custom error message"]
deps_require_cap() {
    local cap="${1:-}"
    local msg="${2:-Required capability '$cap' not available}"
    
    if ! deps_can "$cap"; then
        echo "[FATAL] $msg" >&2
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Public API - Diagnostics
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Print dependency information for debugging
# Usage: deps_info -> prints formatted tool info
deps_info() {
    echo "nutshell dependency information"
    echo "================================"
    echo ""
    echo "Operating system: $(os_name)"
    echo "Architecture:     $(os_arch)"
    echo ""
    echo "Tool paths and variants:"
    
    local tool path variant
    for tool in sed awk grep perl stat mktemp find sort wc tr head tail cut tee xargs; do
        path="${_TOOL_PATH[$tool]:-}"
        variant="${_TOOL_VARIANT[$tool]:-}"
        
        if [[ -n "$path" ]]; then
            printf "  %-10s %s" "$tool:" "$path"
            [[ -n "$variant" && "$variant" != "standard" ]] && printf " (%s)" "$variant"
            echo ""
        else
            printf "  %-10s NOT FOUND\n" "$tool:"
        fi
    done
    
    echo ""
    echo "Capabilities:"
    local cap val
    for cap in $(deps_caps | sort); do
        echo "  $cap"
    done
}

# @@PUBLIC_API@@
# Check all common tools and report status
# Usage: deps_check -> returns 0 if all basic tools present
deps_check() {
    local required=(sed awk grep stat mktemp find sort wc tr head tail)
    local missing=()
    local tool
    
    for tool in "${required[@]}"; do
        deps_has "$tool" || missing+=("$tool")
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing tools: ${missing[*]}" >&2
        return 1
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# Convenience: Direct tool execution with resolved path
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Run a tool using its detected path
# Usage: deps_run "sed" -i 's/a/b/' file.txt
deps_run() {
    local tool="${1:-}"
    shift
    
    local path="${_TOOL_PATH[$tool]:-}"
    if [[ -z "$path" ]]; then
        echo "[ERROR] Tool '$tool' not available" >&2
        return 1
    fi
    
    "$path" "$@"
}

# -----------------------------------------------------------------------------
# Portable wrappers for common operations with BSD/GNU differences
# These are convenience functions; modules can also access _TOOL_PATH directly
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Portable sed in-place edit
# Usage: deps_sed_inplace "s/old/new/g" "file.txt"
deps_sed_inplace() {
    local pattern="$1"
    local file="$2"
    local sed_path="${_TOOL_PATH[sed]:-sed}"
    
    if deps_is_gnu "sed"; then
        "$sed_path" -i "$pattern" "$file"
    else
        # BSD sed requires argument after -i (backup extension; '' means no backup)
        "$sed_path" -i '' "$pattern" "$file"
    fi
}

# @@PUBLIC_API@@
# Portable stat for file size in bytes
# Usage: deps_stat_size "file" -> "12345"
deps_stat_size() {
    local file="$1"
    local stat_path="${_TOOL_PATH[stat]:-stat}"
    
    if deps_is_gnu "stat"; then
        "$stat_path" -c%s "$file"
    else
        "$stat_path" -f%z "$file"
    fi
}

# @@PUBLIC_API@@
# Portable stat for modification time (epoch seconds)
# Usage: deps_stat_mtime "file" -> "1234567890"
deps_stat_mtime() {
    local file="$1"
    local stat_path="${_TOOL_PATH[stat]:-stat}"
    
    if deps_is_gnu "stat"; then
        "$stat_path" -c%Y "$file"
    else
        "$stat_path" -f%m "$file"
    fi
}
