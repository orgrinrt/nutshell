#!/usr/bin/env bash
# Sourced by tests that need a machine without some tool. Not a test itself.
#
# `_hide_tools jq python` makes `deps` answer that they are not there, whatever
# the machine has. Setting PATH is not enough: `deps` falls back to the usual
# directories after PATH, so a hidden tool has to be refused at the lookup.
# Each test runs in a subshell, so nothing here needs undoing.

[ -n "${_NUTSHELL_FIXTURE_HIDE_TOOLS:-}" ] && return 0
_NUTSHELL_FIXTURE_HIDE_TOOLS=1

_HT_HIDDEN=""

# _hide_tools <tool...> -> the names `deps` will not find, and what it knew is dropped
_hide_tools() {
    if ! declare -F _ht_real_find_tool >/dev/null 2>&1; then
        local src; src="$(declare -f _deps_find_tool)"
        eval "_ht_real${src#_deps}"
        _deps_find_tool() {
            case "$_HT_HIDDEN" in *" $1 "*) return 1 ;; esac
            _ht_real_find_tool "$@"
        }
    fi
    _HT_HIDDEN="$_HT_HIDDEN $* "
    deps_forget
}
