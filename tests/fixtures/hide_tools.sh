#!/usr/bin/env bash
# Sourced by tests that need a machine without some tool. Not a test itself.
#
# `_hide_tools jq python` makes `deps` answer that they are not there, whatever
# the machine has, through `deps_hide`. Each test runs in a subshell, so nothing
# here needs undoing.

[ -n "${_NUTSHELL_FIXTURE_HIDE_TOOLS:-}" ] && return 0
_NUTSHELL_FIXTURE_HIDE_TOOLS=1

# _hide_tools <tool...> -> the names `deps` will not find, and what it knew is dropped
_hide_tools() {
    # What was learned about the rest goes too, as it did when this patched the
    # lookup: a test hides and then expects every answer asked again. A forget
    # first, then the hides, so the modules that picked a tool pick again.
    local _hidden="${NUT_DEPS_HIDE:-}"
    deps_forget
    # shellcheck disable=SC2086
    deps_hide $_hidden "$@"
}
