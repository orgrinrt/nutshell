#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/deps/probe.sh - which capabilities a tool has
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Part of `deps`: the capabilities worked out from the tools that were found, and
# the lazy probe that learns one by running the tool.

[ -n "${_NUTSHELL_DEPS_PROBE_SH:-}" ] && return 0
_NUTSHELL_DEPS_PROBE_SH=1

# What this part stands on.
use super::deps::state

# _deps_probe_toml <capability> <tool> <arguments> <required variant or empty>
#
# Whether the tool turns `a=1` into the json `{"a": 1}`, which is what a
# backend needs of it. The variant is checked first where it decides, so a
# python `yq` is refused without being asked to parse anything. The caller has
# asked `deps_has` for the tool already, so a tool that is there has a path.
# Usage: _deps_probe_toml <capability> <tool> <arguments> <variant> -> sets the capability to 0 or 1
#[pub(super)]
_deps_probe_toml() {
    local IFS=$' \t\n'
    local _cap="$1" _tool="$2" _args="$3" _want="$4" _p _v _out
    _deps_get _p PATH "$_tool"
    _deps_get _v VARIANT "$_tool"
    if [ -n "$_p" ]; then
        if [ -z "$_want" ] || [ "$_v" = "$_want" ]; then
            # `$_args` is words of ours with no spaces inside any of them.
            _out="$(printf 'a = 1\n' | "$_p" $_args 2>/dev/null)" || _out=""
            _out="$(printf '%s' "$_out" | tr -d ' \t\r\n')"
            if [ "$_out" = '{"a":1}' ]; then
                _deps_can_set "$_cap" 1
                return 0
            fi
        fi
    fi
    _deps_can_set "$_cap" 0
}

# Usage: _deps_detect_capabilities -> sets the capabilities of the tools found
#[pub(super)]
_deps_detect_capabilities() {
    # sed capabilities
    if [ -n "${_TOOL_PATH_sed:-}" ]; then
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
        if [ "$variant" = "gnu" ]; then
            _deps_can_set sed_regex_r 1
        else
            _deps_can_set sed_regex_r 0
        fi
    fi
    
    # grep capabilities
    if [ -n "${_TOOL_PATH_grep:-}" ]; then
        local grep_cmd="${_TOOL_PATH_grep}"
        
        # Extended regex (-E)
        _deps_can_set grep_extended 1
        
        # PCRE (-P) - mainly GNU grep
        if echo "test" | "$grep_cmd" -P "t.st" >/dev/null 2>&1; then
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
        if echo "test" | "$grep_cmd" -o "es" >/dev/null 2>&1; then
            _deps_can_set grep_only_matching 1
        else
            _deps_can_set grep_only_matching 0
        fi
    fi
    
    # awk capabilities
    if [ -n "${_TOOL_PATH_awk:-}" ]; then
        local awk_cmd="${_TOOL_PATH_awk}"
        local variant="${_TOOL_VARIANT_awk:-unknown}"
        
        # Regex matching (all awks have this)
        _deps_can_set awk_regex 1
        
        # gawk-specific features
        if [ "$variant" = "gawk" ]; then
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
    if [ -n "${_TOOL_PATH_stat:-}" ]; then
        local stat_cmd="${_TOOL_PATH_stat}"
        local variant="${_TOOL_VARIANT_stat:-unknown}"
        
        # Format strings
        if [ "$variant" = "gnu" ] || [ "$variant" = "bsd" ]; then
            _deps_can_set stat_format 1
        else
            _deps_can_set stat_format 0
        fi
    fi
    
    # perl capabilities
    if [ -n "${_TOOL_PATH_perl:-}" ]; then
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
    if [ -n "${_TOOL_PATH_find:-}" ]; then
        local find_cmd="${_TOOL_PATH_find}"
        local variant="${_TOOL_VARIANT_find:-unknown}"
        
        # -maxdepth (both have it now)
        _deps_can_set find_maxdepth 1
        
        # -printf (GNU only)
        if [ "$variant" = "gnu" ]; then
            _deps_can_set find_printf 1
        else
            _deps_can_set find_printf 0
        fi
    fi
}

