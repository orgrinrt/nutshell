#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/json/build.sh - building JSON from values, with no tool
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# `json_object` and `json_array`: text assembled and escaped in the shell, so
# they work on a machine with none of jq, python and perl. Loaded by
# `lib/json.sh` at the first call of either, which is where a caller gets them.

[ -n "${_NUTSHELL_JSON_BUILD_SH:-}" ] && return 0
_NUTSHELL_JSON_BUILD_SH=1

use string

# A newline and a tab as themselves. There is no `$'\n'` in a POSIX shell to
# write one inline with, so there they are a capture of `printf`, and the
# trailing `.` is because command substitution strips the trailing newline,
# which is the character being asked for. Under bash, the quoting bash has,
# through `eval` so a POSIX shell never parses it: each capture is a fork, and
# this file loads with `json`, before a script's first line.
if [ -n "${BASH_VERSION:-}" ]; then
    eval "_JSON_NL=\$'\\n' _JSON_TAB=\$'\\t'"
else
    _JSON_NL="$(printf '\n.')"; _JSON_NL="${_JSON_NL%.}"
    _JSON_TAB="$(printf '\t.')"; _JSON_TAB="${_JSON_TAB%.}"
fi

# -----------------------------------------------------------------------------

# What `json_object` in `lib/json.sh` prints, where its documentation is.
# Usage: _json_object_build "key1" "value1" ... -> the object
#[pub(super)]
_json_object_build() {
    local result="{"
    local first=1

    while [ $# -ge 2 ]; do
        local key="$1"
        local value="$2"
        shift 2

        [ "$first" -eq 0 ] && result="${result},"
        first=0

        # Escape special characters in value
        # Backslash first. Any other order escapes the backslashes it adds.
        str_replace "$value" '\' '\\' value
        str_replace "$value" '"' '\"' value
        str_replace "$value" "$_JSON_NL" '\n' value
        str_replace "$value" "$_JSON_TAB" '\t' value

        result="${result}""\"${key}\":\"${value}\""
    done

    result="${result}""}"
    echo "$result"
}

# What `json_array` in `lib/json.sh` prints.
# Usage: _json_array_build "a" "b" ... -> the array
#[pub(super)]
_json_array_build() {
    local result="["
    local first=1

    for value in "$@"; do
        [ "$first" -eq 0 ] && result="${result},"
        first=0

        # Escape special characters
        # Backslash first. Any other order escapes the backslashes it adds.
        str_replace "$value" '\' '\\' value
        str_replace "$value" '"' '\"' value
        str_replace "$value" "$_JSON_NL" '\n' value
        str_replace "$value" "$_JSON_TAB" '\t' value

        result="${result}""\"${value}\""
    done

    result="${result}""]"
    echo "$result"
}

