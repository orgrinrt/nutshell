#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/deps/pins.sh - what `[deps.paths]` pins a tool to
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# `deps` asks the manifest which path a tool is pinned to, and this file
# answers through the toml API, so the key is found however TOML spells it:
# under `[deps.paths]`, as `paths.sed` under `[deps]`, as `deps.paths.sed` at
# the root, quoted, or inside an inline table.
#
# This is bash, because the reader is, and `deps` does not load it: a POSIX
# shell refuses it at parse time, and a `use` of it from `deps` would take every
# closure that holds `deps` off the POSIX floor. The entry point loads it and
# it hands `deps` its two functions by name, so where it is not loaded no tool
# is pinned and `deps` resolves each one from PATH.

[ -n "${_NUTSHELL_DEPS_PINS_SH:-}" ] && return 0
_NUTSHELL_DEPS_PINS_SH=1

use toml

# The pinned path, set by `_deps_pin_get`.
_DEPS_PIN=""

# _deps_pin_get <file> <tool> -> `_DEPS_PIN`, the path `[deps.paths]` pins the
# tool to. rc 0 pinned, 1 no pin, 2 a pin that is a table, said on stderr.
#
# The tool is one quoted segment of the path, so a name with a dot in it is
# still one key. A file that is not TOML pins nothing here, and
# `_deps_pin_check` has said so once.
_deps_pin_get() {
    local file="$1" tool="$2" seg path rc=0
    # The floor alone: a backend is picked by asking deps, which is reading this.
    local _TOML_FLOOR_ONLY=1
    _DEPS_PIN=""
    seg="${tool//\\/\\\\}"; seg="${seg//\"/\\\"}"
    path="deps.paths.\"${seg}\""
    if toml_has_section "$file" "$path" 2>/dev/null; then
        printf '[ERROR] deps: [deps.paths] %s in %s is a table, and a pin is a path\n' "$tool" "$file" >&2
        return 2
    fi
    toml_has "$file" "$path" 2>/dev/null || return 1
    _DEPS_PIN="$(toml_get "$file" "$path" 2>/dev/null)" || { _DEPS_PIN=""; return 1; }
    return 0
}

#[pub]
# The path `[deps.paths]` of a manifest pins a tool to, in any spelling TOML
# allows for it.
# Usage: deps_pinned "nut.toml" "sed" -> prints the path; rc 1 when there is no
# pin, rc 2 when the pin is a table
deps_pinned() {
    local rc=0
    _deps_pin_get "$1" "$2" || rc=$?
    [ "$rc" -eq 0 ] && printf '%s\n' "$_DEPS_PIN"
    return "$rc"
}

# _deps_pin_check <file>: says on stderr that the file is not TOML. Refusing
# every tool for it would stop the very run that reports it, so the tools are
# found on PATH and the pins it might hold are not honoured.
_deps_pin_check() {
    local rc=0
    local _TOML_FLOOR_ONLY=1
    toml_has "$1" deps >/dev/null || rc=$?
    [ "$rc" -eq 2 ] || return 0
    printf '[ERROR] deps: no [deps.paths] pin in %s is read\n' "$1" >&2
}

# What `deps` calls, by name.
_DEPS_PIN_GET=_deps_pin_get
_DEPS_PIN_CHECK=_deps_pin_check
