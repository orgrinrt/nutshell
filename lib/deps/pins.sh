#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/deps/pins.sh - what `[deps.paths]` pins a tool to
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# `deps` asks the manifest which path a tool is pinned to, and this file
# answers by reading the manifest through the TOML reader's tree, the same
# reader `toml` answers from. The key is found however TOML spells it: under
# `[deps.paths]`, as `paths.sed` under `[deps]`, as `deps.paths.sed` at the
# root, quoted, or inside an inline table.
#
# This is bash. The reader keeps its tree in associative arrays, which a POSIX
# shell refuses at parse time, so `deps` loads this file only where bash runs
# and elsewhere answers that no tool is pinned.

[ -n "${_NUTSHELL_DEPS_PINS_SH:-}" ] && return 0
_NUTSHELL_DEPS_PINS_SH=1

# The reader loads without `deps`, so this does not make a cycle.
use super::toml::impl::bash

# The pinned path, set by `_deps_pin_get`.
_DEPS_PIN=""

# _deps_pin_get <file> <tool> -> `_DEPS_PIN`, the path `[deps.paths]` pins the
# tool to. rc 0 pinned, 1 no pin, 2 a pin that is not a string, said on stderr.
#
# A file that is not TOML pins nothing here, and `_deps_pin_check` has said so
# once.
_deps_pin_get() {
    local file="$1" tool="$2" rc=0
    _DEPS_PIN=""
    _toml_load "$file" || rc=$?
    [ "$rc" -eq 0 ] || return 1
    _toml_seg_show "$tool"
    _toml_path_split "deps.paths.${_ts_out}" || return 1
    _toml_lookup || return 1
    case "${_TOML_T[$_tl_node]-}" in
        str) _DEPS_PIN="${_TOML_V[$_tl_node]}"; return 0 ;;
    esac
    printf '[ERROR] deps: [deps.paths] %s in %s is not a string\n' "$tool" "$file" >&2
    return 2
}

# _deps_pin_check <file>: says on stderr that the file is not TOML. Refusing
# every tool for it would stop the very run that reports it, so the tools are
# found on PATH and the pins it might hold are not honoured.
_deps_pin_check() {
    local rc=0
    _toml_load "$1" || rc=$?
    [ "$rc" -eq 2 ] || return 0
    printf '[ERROR] deps: %s; no [deps.paths] pin in it is read\n' "$_TOML_ERR" >&2
}
