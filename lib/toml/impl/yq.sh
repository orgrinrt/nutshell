#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/impl/yq.sh - TOML read by mikefarah yq
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The backend `lib/toml.sh` picks where there is no taplo and `deps` finds
# mikefarah yq reading TOML. Only the Go yq: the python one is a jq wrapper
# that reads none. It turns the file's text into JSON, and
# `lib/toml/impl/json_tree.sh` makes the tree of that. The path is `_TOML_TOOL`,
# which `lib/toml.sh` asked `deps` for when it picked this backend.

[ -n "${_NUTSHELL_TOML_IMPL_YQ_SH:-}" ] && return 0
_NUTSHELL_TOML_IMPL_YQ_SH=1

# _toml_tool_json <text> -> `_tt_json`, the text as JSON; non-zero where yq refuses it
# A file with no keys comes back from yq as `null`, which is the empty table.
#[pub(super)]
_toml_tool_json() {
    _tt_json="$(printf '%s' "$1" | "$_TOML_TOOL" -p toml -o json . 2>/dev/null)" || return 1
    [[ "$_tt_json" != null ]] || _tt_json="{}"
}
