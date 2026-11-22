#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/impl/taplo.sh - TOML read by taplo
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The backend `lib/toml.sh` picks where there is no mikefarah yq and `deps`
# finds a taplo that prints TOML as JSON. It turns the file's text into JSON,
# and `lib/toml/impl/json_tree.sh` makes the tree of that.

[ -n "${_NUTSHELL_TOML_IMPL_TAPLO_SH:-}" ] && return 0
_NUTSHELL_TOML_IMPL_TAPLO_SH=1

use deps

# The path is learned once, here, so no later call goes back into `deps`.
_TOML_TAPLO="$(deps_path taplo)"

# _toml_tool_json <text> -> `_tt_json`, the text as JSON; non-zero where taplo refuses it
#[pub(super)]
_toml_tool_json() {
    _tt_json="$(printf '%s' "$1" | "$_TOML_TAPLO" get -o json 2>/dev/null)"
}
