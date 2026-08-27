#!/usr/bin/env bash
# =============================================================================
# nutshell/core/deps.sh - Environment detection and tool availability
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
#[allow(loc = 450)]
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
nut_once || return 0

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

# Declared, not sourced by path. A hand-rolled `source` loads the module and
# hides it from the module-contract check, which reads `use` lines, so the
# dependency was real and unrecorded at once.
use os

# -----------------------------------------------------------------------------
# Configuration file location
# -----------------------------------------------------------------------------

# Find nut.toml - check current dir, then repo root, then nutshell dir
_deps_find_config() {
    local check_paths=(
        "${PWD}/nut.toml"
        "${NUTSHELL_ROOT}/nut.toml"
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

# One variable per entry rather than four associative arrays.
#
# `_TOOL_PATH_sed` holds sed's path, `_TOOL_VARIANT_sed` its variant,
# `_TOOL_CAN_sed_inplace` whether that capability is present, and
# `_TOOL_MISSING_jq` marks a tool looked for and not found.
#
# Every read of these outside this module names the tool literally:
# `${_TOOL_PATH_jq}`, `${_TOOL_PATH_curl}`. A literal name is a plain
# expansion, so the fifteen modules reading them pay nothing at all for the
# change, and four files' worth of array syntax leaves the floor.
#
# Writing needs an `eval`, once per tool at resolution and never on a read.
# Names go through `_deps_name_ok` first, because `deps_has` takes whatever a
# caller hands it and that value now reaches `eval`.
#
# Capability names are kept in a list because `deps_caps` has to report what is
# set, and there is no `${!table[@]}` to ask any more.
declare -g _TOOL_CAN_NAMES=""

# A tool or capability name, as the tail of a variable name. One-to-one.
#
# A name that is already `[A-Za-z0-9_]` and does not begin `enc_` is used as
# itself, so `${_TOOL_PATH_jq}` and `${_TOOL_PATH_grep_pcre}` stay plain
# expansions and the sixteen modules reading them literally pay nothing.
#
# Anything else is hex-encoded whole, behind `enc_`. A name that is safe but
# begins `enc_` takes the encoded path too, which is what makes the mapping
# one-to-one: without that, a tool genuinely called `enc_706b67` would collide
# with `pkg` and one of them would read the other's path.
#
# Refusing instead was tried and was wrong. `deps_has` is documented to look up
# anything not in the eager list, and half the binaries worth asking about have
# a hyphen or a digit in them: `pkg-config`, `git-lfs`, `7z`. Refusing made
# `deps_has pkg-config` answer yes with an empty path, which is the one outcome
# that is worse than either alternative.
_deps_key() {
    case "${1:-}" in
        "" ) _dk=""; return 1 ;;
        enc_* ) : ;;
        [0-9]* ) : ;;
        *[!A-Za-z0-9_]* ) : ;;
        * ) _dk="$1"; return 0 ;;
    esac
    _dk="enc_"
    _dk_in="$1"
    while [ -n "$_dk_in" ]; do
        _dk_c="${_dk_in%"${_dk_in#?}"}"
        _dk_in="${_dk_in#?}"
        _dk="${_dk}$(printf '%02x' "$(printf '%d' "'$_dk_c")")"
    done
    return 0
}

# _deps_get <destvar> <table> <name>
#
# Reads one entry into a variable rather than printing it, so a read costs no
# subshell. Callers outside this module skip it entirely where the name is a
# literal and expand `${_TOOL_PATH_jq}` directly.
_deps_get() {
    _deps_key "$3" || { eval "$1=''"; return 1; }
    eval "$1=\"\${_TOOL_$2_${_dk}:-}\""
}

# _deps_set <table> <name> <value>
_deps_set() {
    _deps_key "$2" || return 1
    eval "_TOOL_$1_${_dk}=\$3"
}

# _deps_can_set <capability> <0|1>
#
# Records the name as well as the value. A fixed list of every capability this
# module knows would report the unset ones as zero, which is a different answer
# than `deps_caps` used to give: it listed what had been set, and an absent
# capability was absent rather than false.
_deps_can_set() {
    _deps_key "$1" || return 1
    case " $_TOOL_CAN_NAMES " in
        *" $1 "*) : ;;
        *) _TOOL_CAN_NAMES="${_TOOL_CAN_NAMES} $1" ;;
    esac
    eval "_TOOL_CAN_${_dk}=\$2"
}

# The config file, found once at init rather than on every lookup.
declare -g _DEPS_CONFIG=""

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

# A probe never reads stdin.
#
# Detection runs a tool with a flag it may not recognise, and a tool given an
# unrecognised flag can fall back to reading a program or a file from standard
# input. When standard input is a terminal, or a pipe nothing ever closes, the
# probe waits there forever and the whole script appears to hang after having
# already printed its output. Closing stdin costs nothing and removes the class.
_deps_detect_sed_variant() {
    local cmd="$1"
    
    # GNU sed has --version
    if "$cmd" --version </dev/null 2>/dev/null | grep -q "GNU"; then
        echo "gnu"
        return
    fi
    
    # BSD sed errors on --version
    if "$cmd" --version </dev/null 2>&1 | grep -qE "(illegal|invalid) option"; then
        echo "bsd"
        return
    fi
    
    echo "unknown"
}

_deps_detect_awk_variant() {
    local cmd="$1"
    
    # GNU awk (gawk)
    if "$cmd" --version </dev/null 2>/dev/null | grep -qi "GNU Awk"; then
        echo "gawk"
        return
    fi
    
    # mawk
    if "$cmd" -W version </dev/null 2>/dev/null | grep -qi "mawk"; then
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
    
    if "$cmd" --version </dev/null 2>/dev/null | grep -q "GNU"; then
        echo "gnu"
        return
    fi
    
    echo "bsd"
}

_deps_detect_stat_variant() {
    local cmd="$1"
    
    # GNU stat has --version
    if "$cmd" --version </dev/null 2>/dev/null | grep -q "GNU"; then
        echo "gnu"
        return
    fi
    
    # BSD stat uses -f for format
    if "$cmd" -f%z / </dev/null 2>/dev/null >/dev/null; then
        echo "bsd"
        return
    fi
    
    echo "unknown"
}

_deps_detect_find_variant() {
    local cmd="$1"
    
    if "$cmd" --version </dev/null 2>/dev/null | grep -q "GNU"; then
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
    if [[ -n "${_TOOL_PATH_sed:-}" ]]; then
        local sed_cmd="${_TOOL_PATH_sed}"
        local variant="${_TOOL_VARIANT_sed:-unknown}"
        
        # In-place editing
        # GNU: sed -i 'cmd' file
        # BSD: sed -i '' 'cmd' file
        _deps_can_set sed_inplace 1
        
        # Extended regex (-E)
        # Both GNU and BSD support -E now
        if "$sed_cmd" -E 's/a/b/' /dev/null 2>/dev/null; then
            _deps_can_set sed_extended 1
        else
            _deps_can_set sed_extended 0
        fi
        
        # GNU-specific -r (same as -E but older)
        if [[ "$variant" == "gnu" ]]; then
            _deps_can_set sed_regex_r 1
        else
            _deps_can_set sed_regex_r 0
        fi
    fi
    
    # grep capabilities
    if [[ -n "${_TOOL_PATH_grep:-}" ]]; then
        local grep_cmd="${_TOOL_PATH_grep}"
        
        # Extended regex (-E)
        _deps_can_set grep_extended 1
        
        # PCRE (-P) - mainly GNU grep
        if echo "test" | "$grep_cmd" -P "t.st" &>/dev/null; then
            _deps_can_set grep_pcre 1
        else
            _deps_can_set grep_pcre 0
        fi
        
        # --include/--exclude for recursive searches
        if "$grep_cmd" --help 2>&1 | grep -q -- '--include'; then
            _deps_can_set grep_include 1
        else
            _deps_can_set grep_include 0
        fi
        
        # -o (only matching)
        if echo "test" | "$grep_cmd" -o "es" &>/dev/null; then
            _deps_can_set grep_only_matching 1
        else
            _deps_can_set grep_only_matching 0
        fi
    fi
    
    # awk capabilities
    if [[ -n "${_TOOL_PATH_awk:-}" ]]; then
        local awk_cmd="${_TOOL_PATH_awk}"
        local variant="${_TOOL_VARIANT_awk:-unknown}"
        
        # Regex matching (all awks have this)
        _deps_can_set awk_regex 1
        
        # gawk-specific features
        if [[ "$variant" == "gawk" ]]; then
            _deps_can_set awk_nextfile 1
            _deps_can_set awk_strftime 1
            _deps_can_set awk_gensub 1
        else
            _deps_can_set awk_nextfile 0
            _deps_can_set awk_strftime 0
            _deps_can_set awk_gensub 0
        fi
    fi
    
    # stat capabilities
    if [[ -n "${_TOOL_PATH_stat:-}" ]]; then
        local stat_cmd="${_TOOL_PATH_stat}"
        local variant="${_TOOL_VARIANT_stat:-unknown}"
        
        # Format strings
        if [[ "$variant" == "gnu" ]] || [[ "$variant" == "bsd" ]]; then
            _deps_can_set stat_format 1
        else
            _deps_can_set stat_format 0
        fi
    fi
    
    # perl capabilities
    if [[ -n "${_TOOL_PATH_perl:-}" ]]; then
        local perl_cmd="${_TOOL_PATH_perl}"
        
        # Basic perl is always capable
        _deps_can_set perl_regex 1
        _deps_can_set perl_inplace 1
        
        # Check for common modules (optional)
        if "$perl_cmd" -MJSON -e '1' 2>/dev/null; then
            _deps_can_set perl_json 1
        else
            _deps_can_set perl_json 0
        fi
    fi
    
    # find capabilities
    if [[ -n "${_TOOL_PATH_find:-}" ]]; then
        local find_cmd="${_TOOL_PATH_find}"
        local variant="${_TOOL_VARIANT_find:-unknown}"
        
        # -maxdepth (both have it now)
        _deps_can_set find_maxdepth 1
        
        # -printf (GNU only)
        if [[ "$variant" == "gnu" ]]; then
            _deps_can_set find_printf 1
        else
            _deps_can_set find_printf 0
        fi
    fi
}

# -----------------------------------------------------------------------------
# Initialization
# -----------------------------------------------------------------------------

_deps_init() {
    local config_file
    config_file="$(_deps_find_config)" || config_file=""
    _DEPS_CONFIG="$config_file"
    
    # List of tools to detect
    local tools=(
        sed awk grep perl stat mktemp find sort wc tr
        head tail dirname basename uname cut tee xargs
    )
    
    local available=()
    local tool path variant
    
    for tool in "${tools[@]}"; do
        if path="$(_deps_find_tool "$tool" "$config_file")"; then
            _deps_set PATH "$tool" "$path"
            available+=("$tool")
            
            # Detect variant for tools that have meaningful variants
            case "$tool" in
                sed)  _deps_set VARIANT "$tool" "$(_deps_detect_sed_variant "$path")" ;;
                awk)  _deps_set VARIANT "$tool" "$(_deps_detect_awk_variant "$path")" ;;
                grep) _deps_set VARIANT "$tool" "$(_deps_detect_grep_variant "$path")" ;;
                stat) _deps_set VARIANT "$tool" "$(_deps_detect_stat_variant "$path")" ;;
                find) _deps_set VARIANT "$tool" "$(_deps_detect_find_variant "$path")" ;;
                *)    _deps_set VARIANT "$tool" standard ;;
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

# Not readonly, deliberately. It was, and that froze the answer rather than the
# source of truth: init scans a fixed list of unix text tools, so a tool found
# later by `deps_has` could never join the list of what is available. An
# immutable cache is a bug wherever the cache is allowed to be incomplete, and
# this one is incomplete by construction.
#
# The associative arrays beside it were never readonly either, since bash
# cannot always make one so. They are written by this module and read by
# everyone; treat them as read-only from outside.

# -----------------------------------------------------------------------------
# Public API - Availability checks
# -----------------------------------------------------------------------------

#[pub]
# Check if a tool is available
# Usage: deps_has "sed" -> returns 0 (true) or 1 (false)
deps_has() {
    local tool="${1:-}"
    [[ -z "$tool" ]] && return 1
    local _hit
    _deps_get _hit PATH "$tool"    && [[ -n "$_hit" ]] && return 0
    _deps_get _hit MISSING "$tool" && [[ -n "$_hit" ]] && return 1

    # Anything not in the eager list is looked for now, once, and remembered.
    #
    # Without this, `deps_has` answered no for every tool init did not scan
    # for, and init scans for the unix text tools. So `json.sh` asked for jq
    # and was told no on a machine with jq, and fell through its documented
    # "jq, then python, then perl" preference to perl every time; `http.sh`
    # asked for curl and for wget, was told no to both, and reported itself
    # unavailable on every machine there has ever been. Neither module was
    # wrong to ask. The answer was.
    local path
    if path="$(_deps_find_tool "$tool" "$_DEPS_CONFIG")"; then
        _deps_set PATH "$tool" "$path"
        _TOOLS_AVAILABLE="${_TOOLS_AVAILABLE} ${tool}"
        return 0
    fi
    _deps_set MISSING "$tool" 1
    return 1
}

#[pub]
# Check if multiple tools are all available
# Usage: deps_has_all "sed" "awk" "grep" -> returns 0 if all present
deps_has_all() {
    local tool
    for tool in "$@"; do
        # Through deps_has, so a tool outside the eager list is looked for.
        # Reading the table straight made the answer depend on whether
        # something else had asked about the tool first, and the whole point of
        # this module is that the answer does not depend on load order.
        deps_has "$tool" || return 1
    done
    return 0
}

#[pub]
# Check if at least one of the tools is available
# Usage: deps_has_any "perl" "sed" -> returns 0 if any present
deps_has_any() {
    local tool
    for tool in "$@"; do
        deps_has "$tool" && return 0
    done
    return 1
}

#[pub]
# Get the list of available tools (space-separated)
# Usage: deps_available -> "sed awk grep perl stat..."
deps_available() {
    echo "$_TOOLS_AVAILABLE"
}

# -----------------------------------------------------------------------------
# Public API - Path and variant access
# -----------------------------------------------------------------------------

#[pub]
# Get the path to a tool
# Usage: deps_path "sed" -> "/usr/bin/sed"
deps_path() {
    local tool="${1:-}"
    # Through deps_has, so a tool outside the eager list resolves here too. The
    # two used to disagree: asking whether a tool was there found it, and
    # asking where it was did not, because only the first had been taught to
    # look.
    deps_has "$tool" || return 1
    local _p; _deps_get _p PATH "$tool"
    printf '%s\n' "$_p"
}

#[pub]
# Get the variant of a tool
# Usage: deps_variant "sed" -> "gnu" or "bsd"
deps_variant() {
    local tool="${1:-}"
    local _v; _deps_get _v VARIANT "$tool"
    echo "${_v:-unknown}"
}

#[pub]
# Check if tool is GNU variant
# Usage: deps_is_gnu "sed" -> returns 0 or 1
deps_is_gnu() {
    local tool="${1:-}"
    local variant; _deps_get variant VARIANT "$tool"
    [[ "$variant" == "gnu" ]] || [[ "$variant" == "gawk" ]]
}

#[pub]
# Check if tool is BSD variant
# Usage: deps_is_bsd "sed" -> returns 0 or 1
deps_is_bsd() {
    local tool="${1:-}"
    local variant; _deps_get variant VARIANT "$tool"
    [[ "$variant" == "bsd" ]]
}

# -----------------------------------------------------------------------------
# Public API - Capability checks
# -----------------------------------------------------------------------------

#[pub]
# Check if a capability is available
# Usage: deps_can "grep_pcre" -> returns 0 or 1
deps_can() {
    local cap="${1:-}"
    local _c; _deps_get _c CAN "$cap"
    [[ "${_c:-0}" == "1" ]]
}

#[pub]
# Get capability value (1 or 0)
# Usage: deps_cap "grep_pcre" -> "1" or "0"
deps_cap() {
    local cap="${1:-}"
    local _c; _deps_get _c CAN "$cap"
    echo "${_c:-0}"
}

#[pub]
# List all capabilities (one per line: cap=value)
# Usage: deps_caps -> "sed_inplace=1\ngrep_pcre=1\n..."
deps_caps() {
    local cap _c
    for cap in $_TOOL_CAN_NAMES; do
        _deps_get _c CAN "$cap"
        echo "${cap}=${_c}"
    done | sort
}

# -----------------------------------------------------------------------------
# Public API - Requirement enforcement
# -----------------------------------------------------------------------------

#[pub]
# Require a tool to be present; exit if not
# Usage: deps_require "sed" ["Custom error message"] -> prints nothing; does not return when the tool is missing, it exits
deps_require() {
    local tool="${1:-}"
    local msg="${2:-Required tool '$tool' not found}"
    
    if ! deps_has "$tool"; then
        echo "[FATAL] $msg" >&2
        exit 1
    fi
}

#[pub]
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

#[pub]
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

#[pub]
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
        _deps_get path PATH "$tool"
        _deps_get variant VARIANT "$tool"
        
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

#[pub]
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

#[pub]
# Run a tool using its detected path
# Usage: deps_run "sed" -i 's/a/b/' file.txt
deps_run() {
    local tool="${1:-}"
    shift

    local path
    if ! path="$(deps_path "$tool")"; then
        echo "[ERROR] Tool '$tool' not available" >&2
        return 1
    fi

    "$path" "$@"
}

# -----------------------------------------------------------------------------
# Portable wrappers for common operations with BSD/GNU differences
# These are convenience functions; modules can also access _TOOL_PATH directly
# -----------------------------------------------------------------------------

#[pub]
# Portable sed in-place edit
# Usage: deps_sed_inplace "s/old/new/g" "file.txt"
deps_sed_inplace() {
    local pattern="$1"
    local file="$2"
    local sed_path="${_TOOL_PATH_sed:-sed}"
    
    if deps_is_gnu "sed"; then
        "$sed_path" -i "$pattern" "$file"
    else
        # BSD sed requires argument after -i (backup extension; '' means no backup)
        "$sed_path" -i '' "$pattern" "$file"
    fi
}

#[pub]
# Portable stat for file size in bytes
# Usage: deps_stat_size "file" -> "12345"
deps_stat_size() {
    local file="$1"
    local stat_path="${_TOOL_PATH_stat:-stat}"
    
    if deps_is_gnu "stat"; then
        "$stat_path" -c%s "$file"
    else
        "$stat_path" -f%z "$file"
    fi
}

#[pub]
# Portable stat for modification time (epoch seconds)
# Usage: deps_stat_mtime "file" -> "1234567890"
deps_stat_mtime() {
    local file="$1"
    local stat_path="${_TOOL_PATH_stat:-stat}"
    
    if deps_is_gnu "stat"; then
        "$stat_path" -c%Y "$file"
    else
        "$stat_path" -f%m "$file"
    fi
}
