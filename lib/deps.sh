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

# The hide list this process was started with, the parent's word: a forget
# clears what `deps_hide` added here and keeps this.
_DEPS_ENV_HIDE="${NUT_DEPS_HIDE:-}"

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

# Declared, not sourced by path, so the module-contract check sees them. What a
# presence question needs is loaded here; `os` (for `deps_info`), the variant
# probes and the capability probes are loaded by the first question that needs
# them, because a hook asks `deps_has` on every tool call and a `use` costs
# about a millisecond before the file has run a line.
use key super::deps::state super::deps::config

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
    _DEPS_CONFIG=""; _deps_find_config && _DEPS_CONFIG="$_DEPS_FOUND_CONFIG"
    [ "$_DEPS_CONFIG" != "$old" ] || return 0
    for _k in $_DEPS_SEEN; do eval "unset _TOOL_MISSING_${_k}"; done
    _DEPS_PIN_SAID="" _DEPS_TXT_OF=""
    [ -n "$_DEPS_CONFIG" ] || return 0
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
    use super::deps::probe || return 0
    case "$1" in
        toml_read)        deps_has yq >/dev/null 2>&1 || true
                          _deps_probe_toml "toml_read" yq "-p toml -o json ." mikefarah ;;
        toml_json_taplo)  deps_has taplo >/dev/null 2>&1 || true
                          _deps_probe_toml "toml_json_taplo" taplo "get -o json" "" ;;
    esac
    return 0
}

# Every tool, resolved, for the two whole-table questions: what is available,
# and which capabilities are present. Resolving all eighteen at load cost 125ms
# of a 148ms module load, so it is asked for instead. Inside a substitution it
# scans in the subshell and the parent keeps none of it, so
# `x="$(deps_available)"` scans every time; neither question is asked in a loop,
# and the hot path, `deps_has` called directly, keeps what it learns.
_deps_scan_all() {
    [ "${_DEPS_SCANNED:-0}" = "1" ] && return 0
    _DEPS_SCANNED=1
    use super::deps::probe || return 1
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
    case " ${NUT_DEPS_HIDE:-} " in *" $tool "*) return 1 ;; esac
    [ "${_NUT_ASKING_FROM:-}|${NUTSHELL_SCRIPT_DIR:-}|${PWD}" = "$_DEPS_CONFIG_KEY" ] || _deps_sync_config
    local _hit
    _deps_get _hit PATH "$tool"    && [ -n "$_hit" ] && return 0
    _deps_get _hit MISSING "$tool" && [ -n "$_hit" ] && return 1

    # Anything not known is looked for now, once, and remembered. Answering no
    # for what nobody had scanned for once sent `json` to perl beside a jq.
    local path
    if _deps_find_tool "$tool" "$_DEPS_CONFIG"; then
        path="$_DEPS_FOUND"
        _deps_set PATH "$tool" "$path"
        # Seven tools come in variants worth a probe, and the probes are loaded
        # for those alone.
        case "$tool" in
            sed|awk|grep|stat|find|yq|taplo)
                use super::deps::variants && _deps_set_variant "$tool" "$path" ;;
            *)  _deps_set VARIANT "$tool" standard ;;
        esac
        _TOOLS_AVAILABLE="${_TOOLS_AVAILABLE} ${tool}"
        return 0
    fi
    # Remembered like any miss, so a bad manifest entry is said once and not on
    # every question.
    _deps_set MISSING "$tool" 1
    return 1
}

#[pub]
# Answer absent for tools the machine may well have, so a script or a test runs
# the path a machine without them takes. `deps_run` refuses them too. Kept in
# `NUT_DEPS_HIDE`, a space-separated list, exported, so a child process of this
# one hides them as well; set it in the environment to hide tools from a child.
# Usage: deps_hide "jq" ["python" ...] -> hides each, forgetting where it was found
deps_hide() {
    local _t
    for _t in "$@"; do
        [ -n "$_t" ] || continue
        case " ${NUT_DEPS_HIDE:-} " in *" $_t "*) ;; *) NUT_DEPS_HIDE="${NUT_DEPS_HIDE:+${NUT_DEPS_HIDE} }${_t}" ;; esac
        _deps_unlearn "$_t" || true
    done
    export NUT_DEPS_HIDE
    _deps_drop_caps
    _deps_reset_modules
    return 0
}

#[pub]
# Forget what was learned about tools, so the next question looks again, and
# what `deps_hide` hid. A miss is remembered for the life of the process, which
# is right until something installs the tool. The manifest is read again too.
# Usage: deps_forget [tool...] -> forgets the named tools, or every one
deps_forget() {
    local _t _k _new=""
    if [ "$#" -eq 0 ]; then
        for _k in $_DEPS_SEEN; do
            eval "unset _TOOL_PATH_${_k} _TOOL_VARIANT_${_k} _TOOL_MISSING_${_k}"
        done
        _DEPS_SEEN=""
        _TOOLS_AVAILABLE=""
        if [ -n "$_DEPS_ENV_HIDE" ]; then NUT_DEPS_HIDE="$_DEPS_ENV_HIDE"; export NUT_DEPS_HIDE; else unset NUT_DEPS_HIDE; fi
    else
        for _t in "$@"; do _deps_unlearn "$_t" || true; done
        for _k in ${NUT_DEPS_HIDE:-}; do
            case " $* " in *" $_k "*) ;; *) _new="${_new:+${_new} }${_k}" ;; esac
        done
        [ -z "${NUT_DEPS_HIDE:-}" ] || NUT_DEPS_HIDE="$_new"
    fi
    _deps_drop_caps
    _DEPS_CONFIG=""
    _DEPS_CONFIG_KEY=""
    _deps_reset_modules
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
    use os || return 1
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
        case " ${NUT_DEPS_HIDE:-} " in
            *" $tool "*) echo "[ERROR] Tool '$tool' is hidden (NUT_DEPS_HIDE)" >&2; return 1 ;;
        esac
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
