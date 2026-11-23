#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/deps/config.sh - where the manifest is, and which tool a pin names
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Part of `deps`: finds the `nut.toml` of the unit that is running, and resolves
# a tool to a path, a pin in `[deps.paths]` first.

[ -n "${_NUTSHELL_DEPS_CONFIG_SH:-}" ] && return 0
_NUTSHELL_DEPS_CONFIG_SH=1

# Find nut.toml, walking up from the unit that is running, the way `extern`
# finds a script's manifest: the asking file, the entry point, then the working
# directory, each searched upward. A script's tool paths belong to the script,
# so one run against another repository still reads its own `[deps.paths]`.
# Nutshell's own manifest is the last resort.
#
# Into a variable rather than printed: the capture around it was a fork on the
# first tool question of every process.
# Usage: _deps_find_config -> `_DEPS_FOUND_CONFIG`, the nut.toml that applies, rc 1 when there is none
#[pub(super)]
_deps_find_config() {
    local start dir
    _DEPS_FOUND_CONFIG=""
    for start in "${_NUT_ASKING_FROM:-}" "${NUTSHELL_SCRIPT_DIR:-}" "${PWD}"; do
        [ -n "$start" ] || continue
        dir="$start"
        while [ -n "$dir" ] && [ "$dir" != "/" ]; do
            if [ -f "${dir}/nut.toml" ]; then
                _DEPS_FOUND_CONFIG="${dir}/nut.toml"
                return 0
            fi
            case "$dir" in */*) dir="${dir%/*}" ;; *) break ;; esac
        done
    done
    if [ -n "${NUTSHELL_ROOT:-}" ] && [ -f "${NUTSHELL_ROOT}/nut.toml" ]; then
        _DEPS_FOUND_CONFIG="${NUTSHELL_ROOT}/nut.toml"
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Internal: Path resolution
# -----------------------------------------------------------------------------

# Find tool path using resolution order:
# 1. User config (nut.toml [deps.paths])
# 2. The first executable file of that name on PATH, as `which` finds it
# 3. Common locations, verified for executability
#
# Returns 1 for a tool that is not there and 2 for an entry in `[deps.paths]`
# that names something which is not an executable file. The second is a fault
# in the manifest, said once on stderr, and it never falls through to PATH: an
# override that silently pins nothing is worse than having none.
#
# The answer goes into a variable, and PATH is walked here rather than by
# running `which`: `deps_has` captured this, so each tool a process asked about
# cost a fork and an exec, and the first one also loaded `deps::pins` and read
# the manifest inside the capture, where all of it was thrown away.
# Usage: _deps_find_tool <tool> <config file> -> `_DEPS_FOUND`, rc 1 when absent, rc 2 on a refused pin
#[pub(super)]
_deps_find_tool() {
    local tool="$1"
    local config_file="$2"
    _DEPS_FOUND=""

    # 1. Check user config first
    if [ -n "$config_file" ]; then
        local user_path rc=0
        _deps_pin "$config_file" "$tool" || rc=$?
        [ "$rc" -eq 2 ] && return 2
        if [ "$rc" -eq 0 ]; then
            user_path="$_DEPS_PIN"
            if [ -f "$user_path" ] && [ -x "$user_path" ]; then
                _DEPS_FOUND="$user_path"
                return 0
            fi
            printf '[ERROR] deps: [deps.paths] %s = "%s" is not an executable file (%s)\n' \
                "$tool" "$user_path" "$config_file" >&2
            return 2
        fi
    fi

    # 2. PATH, element by element. An empty element is the working directory.
    local rest="${PATH:-}:" dir
    while [ -n "$rest" ]; do
        dir="${rest%%:*}"; rest="${rest#*:}"
        [ -n "$dir" ] || dir="."
        if [ -f "${dir}/${tool}" ] && [ -x "${dir}/${tool}" ]; then
            _DEPS_FOUND="${dir}/${tool}"
            return 0
        fi
    done

    # 3. Check common locations
    # The prefixes rather than the joined paths, so the list is words with no
    # spaces in any of them and splitting it is safe. A tool name with a space
    # in it is not a tool name.
    for dir in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
        if [ -x "${dir}/${tool}" ]; then
            _DEPS_FOUND="${dir}/${tool}"
            return 0
        fi
    done

    # Not found
    return 1
}

# Which functions answer `[deps.paths]`, by name. That is `deps::pins`, which is
# bash and reads the manifest through the toml API; a POSIX shell refuses it at
# parse time, and a `use` of it from `deps` would take every closure that holds
# `deps` off the POSIX floor. So `init` names two functions that load it on the
# first pin asked for, and every script that loads nutshell has its pins read.
# `deps.sh` sourced bare has none: no tool is pinned and each is resolved from
# PATH.
: "${_DEPS_PIN_GET:=}"
: "${_DEPS_PIN_CHECK:=}"
_DEPS_PIN=""

# The two pin functions are `deps::pins`', handed over by name when it is
# loaded. Called through these, which answer "no pin" and "fine" where it is not.
# Usage: _deps_pin <file> <tool> -> `_DEPS_PIN`; rc 0 pinned, 1 no pin, 2 refused
#[pub(super)]
_deps_pin() {
    _DEPS_PIN=""
    [ -n "$_DEPS_PIN_GET" ] || return 1
    "$_DEPS_PIN_GET" "$1" "$2"
}

# Usage: _deps_pin_verify <file> -> says on stderr when the manifest cannot be read
#[pub(super)]
_deps_pin_verify() {
    [ -n "$_DEPS_PIN_CHECK" ] || return 0
    "$_DEPS_PIN_CHECK" "$1"
}
