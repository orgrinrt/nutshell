#!/usr/bin/env bash
# =============================================================================
# nutshell/core/deps.sh - Environment detection and tool availability
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer -1 (Foundation): Depends only on os.sh and key.sh. Its parts are
# `lib/deps/`: the tables, the variants, the manifest and the capabilities, which
# call nothing here; this file is the API.
#
# This module detects what external tools are available and collects
# information about them (paths, variants, capabilities). It does NOT
# decide which tool is "best" for any operation; that's the job of
# the module that actually uses the tool.
#
# A tool is looked for the first time it is asked about, and the answer is kept
# in plain variables, one per entry.
#
# Configuration:
#   Tool paths can be overridden in nut.toml under [deps.paths]:
#     [deps.paths]
#     sed = "/opt/gnu/bin/sed"
#     awk = "/usr/local/bin/gawk"
# =============================================================================

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and so
# needs bash. Under a POSIX shell `nut_once` is simply not found, and the
# `|| return 0` after it then fires on every load: the module reports success
# and defines nothing.
[ -n "${_NUTSHELL_DEPS_SH:-}" ] && return 0
_NUTSHELL_DEPS_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

# Declared, not sourced by path. A hand-rolled `source` loads the module and
# hides it from the module-contract check, which reads `use` lines, so the
# dependency was real and unrecorded at once.
use os key

# The rest of the module, split by concern, loaded ahead of what this file runs
# when it is sourced.
use super::deps::state super::deps::variants super::deps::config super::deps::probe

# The manifest follows the unit that is running, and the entry point is only
# known once the interpreter has set it: a module loaded earlier than that sees
# the working directory's answer. So the answer is kept with what it was derived
# from, and looked for again when any of that changes.
#
# When the manifest turns out to be a different file, a tool already resolved
# under the old one that the new one pins is resolved again, and misses are
# forgotten, so an entry in the script's own `[deps.paths]` takes effect
# whatever got to the tool first.
_deps_sync_config() {
    local old="$_DEPS_CONFIG" t _k _rc
    _DEPS_CONFIG_KEY="${_NUT_ASKING_FROM:-}|${NUTSHELL_SCRIPT_DIR:-}|${PWD}"
    _DEPS_CONFIG="$(_deps_find_config)" || _DEPS_CONFIG=""
    [ "$_DEPS_CONFIG" != "$old" ] || return 0
    for _k in $_DEPS_SEEN; do eval "unset _TOOL_MISSING_${_k}"; done
    [ -n "$_DEPS_CONFIG" ] || return 0
    _deps_pin_verify "$_DEPS_CONFIG"
    local list="$_TOOLS_AVAILABLE"
    for t in $list; do
        _rc=0; _deps_pin "$_DEPS_CONFIG" "$t" >/dev/null 2>&1 || _rc=$?
        [ "$_rc" -eq 1 ] && continue
        _deps_unlearn "$t"
        deps_has "$t" >/dev/null 2>&1 || true
        _deps_drop_caps
    done
}

# Capabilities that cost a run of an external program to learn. Unlike the ones
# in `_deps_detect_capabilities` they are not part of the scan: the probe runs
# the first time the capability is asked for, and the answer is kept. They show
# in `deps_caps` once asked.
_deps_probe_cap() {
    case " $_TOOL_CAN_NAMES " in *" $1 "*) return 0 ;; esac
    case "$1" in
        toml_read)        deps_has yq >/dev/null 2>&1 || true
                          _deps_probe_toml "toml_read" yq "-p toml -o json ." mikefarah ;;
        toml_json_taplo)  deps_has taplo >/dev/null 2>&1 || true
                          _deps_probe_toml "toml_json_taplo" taplo "get -o json" "" ;;
    esac
    return 0
}

# Every tool, resolved. What the load used to do, now asked for: resolving all
# eighteen at load cost 125ms of a 148ms module load, on a path every consumer
# of `fs` and `text` takes because they declare `use deps`. `deps_has` resolves
# a tool it has not seen and remembers a miss, so the eager pass was a prefetch
# of answers most callers never ask for.
#
# Only two questions need it: what is available, and which capabilities are
# present. Both are whole-table questions and neither is asked by a module
# picking an implementation.
# What it costs to be called inside a command substitution, which is worth
# stating because it is not obvious and it bit the test that pins capabilities:
# a substitution is a subshell, so the scan happens there and the parent keeps
# none of it. `x="$(deps_available)"` therefore scans every time it is called.
#
# The hot path is unaffected, because it is not a substitution: a dispatcher
# calls `deps_has` directly and the answer it records stays in the shell that
# recorded it. Only the two whole-table questions go through a substitution,
# and neither is asked in a loop.
_deps_scan_all() {
    [ "${_DEPS_SCANNED:-0}" = "1" ] && return 0
    _DEPS_SCANNED=1
    local tools="sed awk grep perl stat mktemp find sort wc tr
        head tail dirname basename uname cut tee xargs"
    local tool
    for tool in $tools; do
        deps_has "$tool" >/dev/null 2>&1 || true
    done
    _deps_detect_capabilities
    return 0
}

# -----------------------------------------------------------------------------
# Public API - Availability checks
# -----------------------------------------------------------------------------

#[pub]
# Check if a tool is available
# Usage: deps_has "sed" -> returns 0 (true) or 1 (false)
deps_has() {
    local tool="${1:-}"
    [ -z "$tool" ] && return 1
    [ "${_NUT_ASKING_FROM:-}|${NUTSHELL_SCRIPT_DIR:-}|${PWD}" = "$_DEPS_CONFIG_KEY" ] || _deps_sync_config
    local _hit
    _deps_get _hit PATH "$tool"    && [ -n "$_hit" ] && return 0
    _deps_get _hit MISSING "$tool" && [ -n "$_hit" ] && return 1

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
        _deps_set_variant "$tool" "$path"
        _TOOLS_AVAILABLE="${_TOOLS_AVAILABLE} ${tool}"
        return 0
    fi
    # Remembered like any miss, so a bad manifest entry is said once and not on
    # every question.
    _deps_set MISSING "$tool" 1
    return 1
}

#[pub]
# Forget what was learned about tools, so the next question looks again. A
# miss is remembered for the life of the process, which is right until
# something installs the tool. The manifest is read again as well.
# Usage: deps_forget [tool...] -> forgets the named tools, or every one
deps_forget() {
    local _t _k
    if [ "$#" -eq 0 ]; then
        for _k in $_DEPS_SEEN; do
            eval "unset _TOOL_PATH_${_k} _TOOL_VARIANT_${_k} _TOOL_MISSING_${_k}"
        done
        _DEPS_SEEN=""
        _TOOLS_AVAILABLE=""
    else
        for _t in "$@"; do _deps_unlearn "$_t" || true; done
    fi
    _deps_drop_caps
    _DEPS_CONFIG=""
    _DEPS_CONFIG_KEY=""
    return 0
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
    # The only question that needs every answer, so it is the one that pays.
    _deps_scan_all
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
    # Resolve first. The variant is set when a tool is found, and finding is
    # lazy now, so asking about a tool nobody has asked for reads an empty
    # table and answers `unknown` rather than the truth.
    deps_has "$tool" >/dev/null 2>&1 || true
    local _v; _deps_get _v VARIANT "$tool"
    echo "${_v:-unknown}"
}

#[pub]
# Check if tool is GNU variant
# Usage: deps_is_gnu "sed" -> returns 0 or 1
deps_is_gnu() {
    local tool="${1:-}"
    deps_has "$tool" >/dev/null 2>&1 || true
    local variant; _deps_get variant VARIANT "$tool"
    [ "$variant" = "gnu" ] || [ "$variant" = "gawk" ]
}

#[pub]
# Check if tool is BSD variant
# Usage: deps_is_bsd "sed" -> returns 0 or 1
deps_is_bsd() {
    local tool="${1:-}"
    deps_has "$tool" >/dev/null 2>&1 || true
    local variant; _deps_get variant VARIANT "$tool"
    [ "$variant" = "bsd" ]
}

# -----------------------------------------------------------------------------
# Public API - Capability checks
# -----------------------------------------------------------------------------

#[pub]
# Check if a capability is available
# Usage: deps_can "grep_pcre" -> returns 0 or 1
deps_can() {
    # Capabilities are probed against the tools that were found, so the scan
    # has to have happened. It is once per process.
    _deps_scan_all
    local cap="${1:-}"
    _deps_probe_cap "$cap"
    local _c; _deps_get _c CAN "$cap"
    [ "${_c:-0}" = "1" ]
}

#[pub]
# Get capability value (1 or 0)
# Usage: deps_cap "grep_pcre" -> "1" or "0"
deps_cap() {
    # The scan, for the same reason `deps_can` needs it: capabilities are
    # probed against the tools that were found. One letter apart from
    # `deps_can` and it was the one that did not, which is exactly where this
    # went wrong.
    _deps_scan_all
    local cap="${1:-}"
    _deps_probe_cap "$cap"
    local _c; _deps_get _c CAN "$cap"
    echo "${_c:-0}"
}

#[pub]
# List all capabilities (one per line: cap=value)
# Usage: deps_caps -> "sed_inplace=1\ngrep_pcre=1\n..."
deps_caps() {
    _deps_scan_all
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
    local missing=""
    local tool

    for tool in "$@"; do
        deps_has "$tool" || missing="${missing} ${tool}"
    done

    if [ -n "$missing" ]; then
        echo "[FATAL] Required tools not found: ${missing# }" >&2
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
        
        if [ -n "$path" ]; then
            printf "  %-10s %s" "$tool:" "$path"
            [ -n "$variant" ] && [ "$variant" != "standard" ] && printf " (%s)" "$variant"
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
    local required="sed awk grep stat mktemp find sort wc tr head tail"
    local missing=""
    local tool

    for tool in $required; do
        deps_has "$tool" || missing="${missing} ${tool}"
    done

    if [ -n "$missing" ]; then
        echo "Missing tools: ${missing# }" >&2
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
