#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/impl/yq.sh - TOML read by mikefarah yq
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The backend `lib/toml.sh` picks where there is no taplo and `deps` finds
# mikefarah yq reading TOML. Only the Go yq: the python one is a jq wrapper
# that reads none. It turns the file's text into JSON, and
# `lib/toml/impl/from_json.sh` makes the tree of that. The path is
# `_TOML_TOOL`, which `lib/toml.sh` asked `deps` for when it picked this backend.
#
# yq prints a float as a JSON number, `3.0` as `3`, so the int and the float
# would be one. It keeps the file's text of every float, though, and hands it
# over as an object whose one key is the unit separator and `f`, which no key
# of the file can be: `from_json.sh` refuses a key holding one. A date-time
# comes back as the file wrote it; one yq would rewrite it refuses instead.

[ -n "${_NUTSHELL_TOML_IMPL_YQ_SH:-}" ] && return 0
_NUTSHELL_TOML_IMPL_YQ_SH=1

# The types whose text this tool gives other than `lib/toml.sh` names it: none.
_TOML_TOOL_REWRITES=""

# _toml_tool_json <text> -> `_tt_json`, the text as JSON; non-zero where yq refuses it
# A file with no keys comes back from yq as `null`, which is the empty table.
#[pub(super)]
_toml_tool_json() {
    _tt_json="$(printf '%s' "$1" | NUT_TOML_FLOAT="${_TOML_US}f" "$_TOML_TOOL" -p toml -o json \
        '(.. | select(tag == "!!float")) |= {strenv(NUT_TOML_FLOAT): to_string}' 2>/dev/null)" || return 1
    [[ "$_tt_json" != null ]] || _tt_json="{}"
}
