#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/impl/yq.sh - TOML read by mikefarah yq
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The backend `lib/toml.sh` picks where `deps` finds mikefarah's yq and it
# reads TOML. Only the Go yq: the python one is a jq wrapper that reads none.
# It turns the file's text into JSON, and `lib/toml/impl/json_tree.sh` makes
# the tree of that.

[ -n "${_NUTSHELL_TOML_IMPL_YQ_SH:-}" ] && return 0
_NUTSHELL_TOML_IMPL_YQ_SH=1

use deps

# The path is learned once, here, so no later call goes back into `deps`.
_TOML_YQ="$(deps_path yq)"

# _toml_tool_json <text> -> `_tt_json`, the text as JSON; non-zero where yq refuses it
# A file with no keys comes back from yq as `null`, which is the empty table.
#[pub(super)]
_toml_tool_json() {
    _tt_json="$(printf '%s' "$1" | "$_TOML_YQ" -p toml -o json . 2>/dev/null)" || return 1
    [[ "$_tt_json" != null ]] || _tt_json="{}"
}
