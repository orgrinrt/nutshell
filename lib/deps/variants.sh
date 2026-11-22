#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/deps/variants.sh - which flavour of a tool this is
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Part of `deps`: asks a binary what it is, since the name does not say (BSD or
# GNU, mikefarah's yq or the python one).

[ -n "${_NUTSHELL_DEPS_VARIANTS_SH:-}" ] && return 0
_NUTSHELL_DEPS_VARIANTS_SH=1

# What this part stands on.
use super::deps::state

# _deps_set_variant <tool> <path>
#
# Which flavour of a tool this is, recorded where the dispatchers look. It was
# inline in the eager scan and is a function because `deps_has` resolves a tool
# too, and a tool resolved that way had no variant at all: `fs.sh` reads
# `${_TOOL_VARIANT_stat:-unknown}` and takes a `uname` guess when it is empty,
# so a lazily resolved `stat` silently took the fallback path.
# Usage: _deps_set_variant <tool> <path> -> records which variant of the tool it is
#[pub(super)]
_deps_set_variant() {
    case "$1" in
        sed)  _deps_set VARIANT "$1" "$(_deps_detect_sed_variant "$2")" ;;
        awk)  _deps_set VARIANT "$1" "$(_deps_detect_awk_variant "$2")" ;;
        grep) _deps_set VARIANT "$1" "$(_deps_detect_grep_variant "$2")" ;;
        stat) _deps_set VARIANT "$1" "$(_deps_detect_stat_variant "$2")" ;;
        find) _deps_set VARIANT "$1" "$(_deps_detect_find_variant "$2")" ;;
        yq)    _deps_set VARIANT "$1" "$(_deps_detect_yq_variant "$2")" ;;
        taplo) _deps_set VARIANT "$1" "$(_deps_detect_taplo_variant "$2")" ;;
        *)    _deps_set VARIANT "$1" standard ;;
    esac
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
    if [ "$(basename "$cmd")" = "nawk" ]; then
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

# Two programs are called `yq`: mikefarah's, a Go binary that reads TOML, and the
# python wrapper over jq, which does not. The name cannot tell them apart, so
# the binary is asked. Only `mikefarah` counts for TOML.
_deps_detect_yq_variant() {
    local out
    out="$("$1" --version </dev/null 2>&1)" || { echo "unknown"; return; }
    case "$out" in
        '')              echo "unknown" ;;
        *mikefarah/yq*)  echo "mikefarah" ;;
        *)               echo "python" ;;
    esac
}

# `taplo` is taplo-cli when it says so, and anything else answering to the name
# is not known.
_deps_detect_taplo_variant() {
    local out
    out="$("$1" --version </dev/null 2>&1)" || { echo "unknown"; return; }
    case "$out" in
        taplo\ *) echo "taplo" ;;
        *)        echo "unknown" ;;
    esac
}

