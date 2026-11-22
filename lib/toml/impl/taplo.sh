#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/impl/taplo.sh - TOML read by taplo
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The backend `lib/toml.sh` picks first, where `deps` finds a taplo that
# prints TOML as JSON, since it refuses a file that is not TOML 1.0. It turns
# the file's text into JSON, and `lib/toml/impl/from_json.sh` makes
# the tree of that. The path is `_TOML_TOOL`, which `lib/toml.sh` asked
# `deps` for when it picked this backend.

[ -n "${_NUTSHELL_TOML_IMPL_TAPLO_SH:-}" ] && return 0
_NUTSHELL_TOML_IMPL_TAPLO_SH=1

# The types whose text this tool gives other than `lib/toml.sh` names it:
# a float, `1e3` as `1000.0` and `1.50` as `1.5`, and a date-time, `+00:00`
# as `Z` and `.500` as `.5`. `from_json.sh` flags each, and the floor answers it.
_TOML_TOOL_REWRITES="float dt"

# _toml_tool_json <text> -> `_tt_json`, the text as JSON; non-zero where taplo refuses it
#[pub(super)]
_toml_tool_json() {
    _tt_json="$(printf '%s' "$1" | "$_TOML_TOOL" get -o json 2>/dev/null)"
}
