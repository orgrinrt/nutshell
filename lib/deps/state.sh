#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/deps/state.sh - what is known about tools, and how it is kept
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Part of `deps`: the tables behind it, one variable per entry, and the
# functions that read, write and drop them. The rest of `deps` stands on this.
# Private to the library: nothing here is an API.

[ -n "${_NUTSHELL_DEPS_STATE_SH:-}" ] && return 0
_NUTSHELL_DEPS_STATE_SH=1

# -----------------------------------------------------------------------------
# Global state
# -----------------------------------------------------------------------------

# Space-separated list of available tools.
_TOOLS_AVAILABLE=""

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
_TOOL_CAN_NAMES=""

# The key encoder lives in `key.sh` now, because it was never about tools: it
# turns any string into the tail of a variable name, and `use` needs the same
# thing for its loaded table. `_deps_key` here is the old spelling, kept as one
# line so the sixteen call sites below do not all have to change at once.
# Usage: _deps_key <name> -> `_dk`, the name as the tail of a variable name
#[pub(lib)]
_deps_key() { nut_key "$1" || return 1; _dk="$_nk"; return 0; }

# _deps_get <destvar> <table> <name>
#
# Reads one entry into a variable rather than printing it, so a read costs no
# subshell. Callers outside this module skip it entirely where the name is a
# literal and expand `${_TOOL_PATH_jq}` directly.
# Usage: _deps_get <destvar> <table> <name> -> the entry, in destvar
#[pub(lib)]
_deps_get() {
    _deps_key "$3" || { eval "$1=''"; return 1; }
    eval "$1=\"\${_TOOL_$2_${_dk}:-}\""
}

# _deps_set <table> <name> <value>
# Usage: _deps_set <table> <name> <value>
#[pub(lib)]
_deps_set() {
    _deps_key "$2" || return 1
    eval "_TOOL_$1_${_dk}=\$3"
    # Every tool asked about, found or not, so `deps_forget` can find them again.
    case "$1" in PATH|MISSING)
        case " $_DEPS_SEEN " in *" $_dk "*) : ;; *) _DEPS_SEEN="${_DEPS_SEEN} ${_dk}" ;; esac ;;
    esac
}

# Encoded keys of every tool that has an entry, space separated.
_DEPS_SEEN=""

# _deps_can_set <capability> <0|1>
#
# Records the name as well as the value. A fixed list of every capability this
# module knows would report the unset ones as zero, which is a different answer
# than `deps_caps` used to give: it listed what had been set, and an absent
# capability was absent rather than false.
# Usage: _deps_can_set <capability> <0|1>
#[pub(lib)]
_deps_can_set() {
    # A capability name has to be a variable name already, and every one this
    # module has is an internal literal like `grep_pcre`. It is not encoded,
    # because `_TOOL_CAN_NAMES` is a space-separated list and `deps_caps`
    # splits it: an encoded name and a raw one in the same list disagree the
    # moment either holds a space, and `deps_caps` then emits two rows with
    # empty values. Tools are caller-supplied and get encoded; capabilities are
    # ours and get refused.
    case "${1:-}" in
        "" | *[!A-Za-z0-9_]* | [0-9]* ) return 1 ;;
    esac
    _dk="$1"
    case " $_TOOL_CAN_NAMES " in
        *" $1 "*) : ;;
        *) _TOOL_CAN_NAMES="${_TOOL_CAN_NAMES} $1" ;;
    esac
    eval "_TOOL_CAN_${_dk}=\$2"
}

# The config file and what it was derived from (see `_deps_sync_config`).
_DEPS_CONFIG=""
_DEPS_CONFIG_KEY=""

# Drop what is known about one tool, so it is looked for again when asked.
# Usage: _deps_unlearn <tool> -> forgets what is known of the tool
#[pub(super)]
_deps_unlearn() {
    local IFS=$' \t\n'
    local _t="$1" _k _w _new
    _deps_key "$_t" || return 1
    _k="$_dk"
    eval "unset _TOOL_PATH_${_k} _TOOL_VARIANT_${_k} _TOOL_MISSING_${_k}"
    _new=""
    for _w in $_DEPS_SEEN; do [ "$_w" = "$_k" ] || _new="${_new} ${_w}"; done
    _DEPS_SEEN="$_new"
    _new=""
    for _w in $_TOOLS_AVAILABLE; do [ "$_w" = "$_t" ] || _new="${_new} ${_w}"; done
    _TOOLS_AVAILABLE="$_new"
}

# Capabilities are derived from the tools, so they go when a tool does and are
# worked out again when next asked.
# Usage: _deps_drop_caps -> forgets every capability
#[pub(super)]
_deps_drop_caps() {
    local IFS=$' \t\n'
    local _w
    for _w in $_TOOL_CAN_NAMES; do eval "unset _TOOL_CAN_${_w}"; done
    _TOOL_CAN_NAMES=""
    _DEPS_SCANNED=0
}


# Not readonly, deliberately. It was, and that froze the answer rather than the
# source of truth: init scans a fixed list of unix text tools, so a tool found
# later by `deps_has` could never join the list of what is available. An
# immutable cache is a bug wherever the cache is allowed to be incomplete, and
# this one is incomplete by construction.
#
# The associative arrays beside it were never readonly either, since bash
# cannot always make one so. They are written by this module and read by
# everyone; treat them as read-only from outside.

# Modules that pick a tool once and keep the pick. Each registers a function
# when it picks, and `deps_hide` and `deps_forget` run them all, so a module
# does not reach into another's state and none is left answering with a tool
# `deps` no longer finds. A hook only drops what its module kept; the next call
# picks again.
_DEPS_RESET_HOOKS=""

# Usage: _deps_reset_modules -> runs every registered hook
#[pub(super)]
_deps_reset_modules() {
    local IFS=$' \t\n'
    local _h
    for _h in $_DEPS_RESET_HOOKS; do "$_h" || true; done
}
