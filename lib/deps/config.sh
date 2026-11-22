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
# Usage: _deps_find_config -> prints the path of the nut.toml that applies, rc 1 when there is none
#[pub(super)]
_deps_find_config() {
    local start dir
    for start in "${_NUT_ASKING_FROM:-}" "${NUTSHELL_SCRIPT_DIR:-}" "${PWD}"; do
        [ -n "$start" ] || continue
        dir="$start"
        while [ -n "$dir" ] && [ "$dir" != "/" ]; do
            if [ -f "${dir}/nut.toml" ]; then
                printf '%s\n' "${dir}/nut.toml"
                return 0
            fi
            case "$dir" in */*) dir="${dir%/*}" ;; *) break ;; esac
        done
    done
    if [ -n "${NUTSHELL_ROOT:-}" ] && [ -f "${NUTSHELL_ROOT}/nut.toml" ]; then
        printf '%s\n' "${NUTSHELL_ROOT}/nut.toml"
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Internal: Path resolution
# -----------------------------------------------------------------------------

# Find tool path using resolution order:
# 1. User config (nut.toml [deps.paths])
# 2. which (if available)
# 3. Common locations, verified for executability
#
# Returns 1 for a tool that is not there and 2 for an entry in `[deps.paths]`
# that names something which is not an executable file. The second is a fault
# in the manifest, said once on stderr, and it never falls through to PATH: an
# override that silently pins nothing is worse than having none.
# Usage: _deps_find_tool <tool> <config file> -> prints the path, rc 1 when absent, rc 2 on a refused pin
#[pub(super)]
_deps_find_tool() {
    local tool="$1"
    local config_file="$2"

    # 1. Check user config first
    if [ -n "$config_file" ]; then
        local user_path rc=0
        _deps_pin "$config_file" "$tool" || rc=$?
        [ "$rc" -eq 2 ] && return 2
        if [ "$rc" -eq 0 ]; then
            user_path="$_DEPS_PIN"
            if [ -f "$user_path" ] && [ -x "$user_path" ]; then
                echo "$user_path"
                return 0
            fi
            printf '[ERROR] deps: [deps.paths] %s = "%s" is not an executable file (%s)\n' \
                "$tool" "$user_path" "$config_file" >&2
            return 2
        fi
    fi
    
    # 2. Try which if available (using command -v to check for which itself)
    if command -v which >/dev/null 2>&1; then
        local found
        found="$(which "$tool" 2>/dev/null)"
        if [ -n "$found" ] && [ -x "$found" ]; then
            echo "$found"
            return 0
        fi
    fi
    
    # 3. Check common locations
    # The prefixes rather than the joined paths, so the list is words with no
    # spaces in any of them and splitting it is safe. A tool name with a space
    # in it is not a tool name.
    local dir
    for dir in /usr/bin /bin /usr/local/bin /opt/homebrew/bin; do
        if [ -x "${dir}/${tool}" ]; then
            echo "${dir}/${tool}"
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
