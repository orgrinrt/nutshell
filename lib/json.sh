#!/usr/bin/env bash
# =============================================================================
# nutshell/core/json.sh - JSON parsing and manipulation
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on deps.sh for tool detection
#
# Reads and writes JSON through the first of jq, python and perl that `deps`
# finds, and reads through bash itself where none of the three is there, so a
# container with no jq still answers `json_get`, `json_has`, `json_keys`,
# `json_type`, `json_length` and `json_valid`. What writes (`json_set`,
# `json_delete`, `json_merge`, `json_pretty`, `json_compact`, `json_write`)
# needs one of the three, and without them refuses with status 2 and says so.
# `json_query` (in `json/query.sh`) runs a jq program through jq, gojq or jaq,
# whichever `deps` finds first that has the options the call uses, and refuses
# with status 2 where there is none.
#
# A path is the one the toml reader takes: `a.b.0.c`, an integer segment
# indexing an array, a segment in double quotes one segment whatever it holds
# (`"k.d".z`), a leading dot allowed.
#
# Object keys come back sorted, and documents come back compact. Not a
# preference: a perl hash has no order and its iteration order is randomised
# per process, so sorted is the only order all backends can produce, and
# `json_pretty` is where formatting lives. Without this the same call returned
# different text depending on which tool happened to be installed, and on perl
# a different order on every run.
#
# Status: 0 found, 1 not there or not JSON, 2 nothing here can do it.
# =============================================================================

# Prevent multiple inclusion
# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded: under a POSIX shell `nut_once` is not found, the `|| return
# 0` returns from the whole file, and the module then defines nothing while
# reporting success.
[ -n "${_NUTSHELL_JSON_SH:-}" ] && return 0
_NUTSHELL_JSON_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

# Declared, not sourced by path. A hand-rolled `source` loads the module and
# hides it from the module-contract check, which reads `use` lines, so the
# dependency was real and unrecorded at once.
use deps
use super::json::build
use super::json::query

# What joins the segments of a path on their way to a backend.
# A capture under a POSIX shell and the quoting bash has under bash, as in
# `json::build`.
if [ -n "${BASH_VERSION:-}" ]; then
    eval "_JSON_US=\$'\\037'"
else
    _JSON_US="$(printf '\037.')"; _JSON_US="${_JSON_US%.}"
fi

# -----------------------------------------------------------------------------
# Backends
# -----------------------------------------------------------------------------
#
# Interchangeable implementations of the same operations, one per tool, in
# `json/impl/`. They lived here and made this file 940 lines, of which the
# public surface was the last fifth. The one in bash needs no tool and only
# reads.
#
# Every backend whose tool is present is loaded, not only the selected one.
# Loading one would save little (they are function definitions) and would make
# `_JSON_IMPL` a decision taken once at load rather than a value the dispatch
# reads, which is what lets a caller move it and lets the tests exercise all of
# them rather than whichever the machine happened to pick.
# Named, not sourced by a path this file assembles. A hand-rolled `source`
# goes around the resolver, so the file is loaded again for every caller that
# reaches it, the declaration does not cover it, and nothing can tell before
# running that the path was wrong.
deps_has jq                             && use super::json::impl::jq
{ deps_has python3 || deps_has python; } && use super::json::impl::python
deps_has perl                           && use super::json::impl::perl
# The path language is the toml reader's, and its splitter is loaded as it is
# rather than copied. Both need bash, so a shell without it keeps the tools.
if [ -n "${BASH_VERSION:-}" ]; then
    use super::toml::impl::bash_path super::json::impl::bash
fi

# -----------------------------------------------------------------------------
# Module Status
# -----------------------------------------------------------------------------

_JSON_READY=0
_JSON_ERROR=""
_JSON_IMPL=""

#[pub]
# Pick the backend again, from what `deps` knows now. Run at load, and after
# `deps_forget` when a tool has come or gone.
# Order: jq, python, perl, then bash, which only reads.
# Usage: json_detect
json_detect() {
    _JSON_READY=1
    _JSON_ERROR=""
    if deps_has jq && type _json_get_jq >/dev/null 2>&1; then
        _JSON_IMPL="jq"
    elif { deps_has python3 || deps_has python; } && type _json_get_python >/dev/null 2>&1; then
        _JSON_IMPL="python"
    elif deps_has perl && type _json_get_perl >/dev/null 2>&1; then
        _JSON_IMPL="perl"
    elif type _json_get_bash >/dev/null 2>&1; then
        _JSON_IMPL="bash"
        _JSON_ERROR="No jq, python or perl: reading only"
    else
        _JSON_READY=0
        _JSON_IMPL=""
        _JSON_ERROR="No JSON tool available (need jq, python, perl or bash)"
    fi
}
json_detect

# _json_segs <path> -> `_js_out`, the segments of a path joined for a backend
# Status 2 when a quote never closes. The splitter is the toml reader's.
_json_segs() {
    local p="${1:-}" seg
    _js_out=""
    case "$p" in .*) p="${p#.}" ;; esac
    [ -z "$p" ] && return 0
    if type _toml_path_split >/dev/null 2>&1; then
        _toml_path_split "$p" || { echo "json: a quote in the path never closes: ${1}" >&2; return 2; }
        for seg in "${_tp_pseg[@]}"; do
            [ -n "$seg" ] && _js_out="${_js_out:+${_js_out}${_JSON_US}}${seg}"
        done
    else
        _js_out="$(printf '%s' "$p" | tr '.' "$_JSON_US")"
    fi
    return 0
}

# _json_ready_for <name> -> status 1 with the reason when nothing can read
_json_ready_for() {
    [ "$_JSON_READY" = "1" ] && return 0
    echo "${1}: ${_JSON_ERROR}" >&2
    return 1
}

# _json_needs_tool <name> -> status 2 with the reason when the selected backend
# cannot write, which is the one in bash.
_json_needs_tool() {
    case "$_JSON_IMPL" in
        jq|python|perl) return 0 ;;
    esac
    echo "${1}: needs jq, python or perl, and this machine has none" >&2
    return 2
}

# -----------------------------------------------------------------------------
# Public API - Reading
# -----------------------------------------------------------------------------

#[pub]
# Get a value from JSON by path
# Usage: json_get '{"foo":"bar"}' "foo" -> "bar"
# Usage: json_get '{"a":{"b":1}}' "a.b" -> "1"
# Usage: json_get '[1,2,3]' "1" -> "2"
# Usage: json_get '{"k.d":{"z":1}}' '"k.d".z' -> "1"
# Returns: The value at the path; status 1 when there is none
json_get() {
    local json="${1:-}"
    [ -z "$json" ] && return 1
    _json_ready_for json_get || return 1
    _json_segs "${2:-}" || return 2
    case "$_JSON_IMPL" in
        jq)     _json_get_jq "$json" "$_js_out" ;;
        python) _json_get_python "$json" "$_js_out" ;;
        perl)   _json_get_perl "$json" "$_js_out" ;;
        bash)   _json_get_bash "$json" "$_js_out" ;;
    esac
}

#[pub]
# Get all keys at a path in JSON
# Usage: json_keys '{"a":1,"b":2}' -> prints "a" and "b" on separate lines
# Usage: json_keys '{"x":{"y":1}}' "x" -> prints "y"
# Returns: Keys, one per line
json_keys() {
    local json="${1:-}"
    [ -z "$json" ] && return 1
    _json_ready_for json_keys || return 1
    _json_segs "${2:-}" || return 2
    case "$_JSON_IMPL" in
        jq)     _json_keys_jq "$json" "$_js_out" ;;
        python) _json_keys_python "$json" "$_js_out" ;;
        perl)   _json_keys_perl "$json" "$_js_out" ;;
        bash)   _json_keys_bash "$json" "$_js_out" ;;
    esac
}

#[pub]
# Check if JSON is valid
# Usage: json_valid '{"foo":"bar"}' -> returns 0 (valid)
# Usage: json_valid 'not json' -> returns 1 (invalid)
# Returns: 0 if valid, 1 if invalid
json_valid() {
    local json="${1:-}"
    [ -z "$json" ] && return 1
    [ "$_JSON_READY" != "1" ] && return 1
    case "$_JSON_IMPL" in
        jq)     _json_valid_jq "$json" ;;
        python) _json_valid_python "$json" ;;
        perl)   _json_valid_perl "$json" ;;
        bash)   _json_valid_bash "$json" ;;
    esac
}

#[pub]
# Get the type of a JSON value
# Usage: json_type '{"a":1}' -> "object"
# Usage: json_type '[1,2]' -> "array"
# Usage: json_type '"str"' -> "string"
# Usage: json_type '123' -> "number"
# Usage: json_type 'true' -> "boolean"
# Usage: json_type 'null' -> "null"
# Returns: "object", "array", "string", "number", "boolean", or "null"
json_type() {
    local json="${1:-}"
    [ -z "$json" ] && return 1
    _json_ready_for json_type || return 1
    _json_segs "${2:-}" || return 2
    case "$_JSON_IMPL" in
        jq)     _json_type_jq "$json" "$_js_out" ;;
        python) _json_type_python "$json" "$_js_out" ;;
        perl)   _json_type_perl "$json" "$_js_out" ;;
        bash)   _json_type_bash "$json" "$_js_out" ;;
    esac
}

#[pub]
# Get the length of a JSON array or object
# Usage: json_length '[1,2,3]' -> "3"
# Usage: json_length '{"a":1,"b":2}' -> "2"
# Returns: Length as number
json_length() {
    local json="${1:-}"
    [ -z "$json" ] && return 1
    _json_ready_for json_length || return 1
    _json_segs "${2:-}" || return 2
    case "$_JSON_IMPL" in
        jq)     _json_length_jq "$json" "$_js_out" ;;
        python) _json_length_python "$json" "$_js_out" ;;
        perl)   _json_length_perl "$json" "$_js_out" ;;
        bash)   _json_length_bash "$json" "$_js_out" ;;
    esac
}

#[pub]
# Check if a path exists in JSON
# Usage: json_has '{"a":{"b":1}}' "a.b" -> returns 0 (exists)
# Usage: json_has '{"a":1}' "b" -> returns 1 (not found)
# Returns: 0 if path exists, 1 otherwise
json_has() {
    local json="${1:-}"
    local path="${2:-}"

    local result
    result=$(json_get "$json" "$path" 2>/dev/null)
    [ -n "$result" ] && [ "$result" != "null" ]
}

#[pub]
# Get value with default if not found
# Usage: json_get_or '{"a":1}' "b" "default" -> "default"
# Usage: json_get_or '{"a":1}' "a" "default" -> "1"
# Returns: Value at path or default
json_get_or() {
    local json="${1:-}"
    local path="${2:-}"
    local default="${3:-}"

    local result
    result=$(json_get "$json" "$path" 2>/dev/null)

    if [ -n "$result" ] && [ "$result" != "null" ]; then
        echo "$result"
    else
        echo "$default"
    fi
}

# -----------------------------------------------------------------------------
# Public API - Writing, which needs jq, python or perl
# -----------------------------------------------------------------------------

#[pub]
# Set a value in JSON by path
# Usage: json_set '{"foo":"bar"}' "foo" "baz" -> '{"foo":"baz"}'
# Usage: json_set '{}' "new.key" "value" -> '{"new":{"key":"value"}}'
# Returns: The modified JSON; status 2 with none of jq, python or perl
json_set() {
    local json="${1:-}" value="${3:-}"
    _json_needs_tool json_set || return 2
    [ -z "$json" ] && return 1
    _json_segs "${2:-}" || return 2
    case "$_JSON_IMPL" in
        jq)     _json_set_jq "$json" "$_js_out" "$value" ;;
        python) _json_set_python "$json" "$_js_out" "$value" ;;
        perl)   _json_set_perl "$json" "$_js_out" "$value" ;;
    esac
}

#[pub]
# Delete a key from JSON
# Usage: json_delete '{"a":1,"b":2}' "a" -> '{"b":2}'
# Returns: JSON with key removed; status 2 with none of jq, python or perl
json_delete() {
    local json="${1:-}"
    _json_needs_tool json_delete || return 2
    _json_segs "${2:-}" || return 2
    case "$_JSON_IMPL" in
        jq)     _json_delete_jq "$json" "$_js_out" ;;
        python) _json_delete_python "$json" "$_js_out" ;;
        perl)   _json_delete_perl "$json" "$_js_out" ;;
    esac
}

#[pub]
# Merge two JSON objects (second overwrites first for conflicts)
# Usage: json_merge '{"a":1}' '{"b":2}' -> '{"a":1,"b":2}'
# Returns: Merged JSON object; status 2 with none of jq, python or perl
json_merge() {
    local json1="${1:-\{\}}" json2="${2:-\{\}}"
    _json_needs_tool json_merge || return 2
    case "$_JSON_IMPL" in
        jq)     _json_merge_jq "$json1" "$json2" ;;
        python) _json_merge_python "$json1" "$json2" ;;
        perl)   _json_merge_perl "$json1" "$json2" ;;
    esac
}

#[pub]
# Pretty print JSON with indentation
# Usage: json_pretty '{"a":1,"b":2}' -> prints formatted JSON
# Returns: Pretty-printed JSON; status 2 with none of jq, python or perl
json_pretty() {
    local json="${1:-}"
    _json_needs_tool json_pretty || return 2
    [ -z "$json" ] && return 1
    case "$_JSON_IMPL" in
        jq)     _json_pretty_jq "$json" ;;
        python) _json_pretty_python "$json" ;;
        perl)   _json_pretty_perl "$json" ;;
    esac
}

#[pub]
# Compact JSON (remove whitespace)
# Usage: json_compact '{ "a": 1, "b": 2 }' -> '{"a":1,"b":2}'
# Returns: Compact JSON on single line; status 2 with none of jq, python or perl
json_compact() {
    local json="${1:-}"
    _json_needs_tool json_compact || return 2
    [ -z "$json" ] && return 1
    case "$_JSON_IMPL" in
        jq)     _json_compact_jq "$json" ;;
        python) _json_compact_python "$json" ;;
        perl)   _json_compact_perl "$json" ;;
    esac
}

#[pub]
# Write JSON to a file (pretty printed)
# Usage: json_write '{"a":1}' "/path/to/file.json"
# Returns: 0 on success, 1 on failure, 2 with none of jq, python or perl, and
# then the file is not touched
json_write() {
    local json="${1:-}"
    local file="${2:-}"

    _json_needs_tool json_write || return 2
    [ -z "$file" ] && return 1

    json_pretty "$json" > "$file"
}

#[pub]
# Read JSON from a file
# Usage: json_read "/path/to/file.json" -> prints JSON content
# Returns: JSON content of file
json_read() {
    local file="${1:-}"

    [ ! -f "$file" ] && { echo "File not found: $file" >&2; return 1; }

    cat "$file"
}

# -----------------------------------------------------------------------------
# Module Status Functions
# -----------------------------------------------------------------------------

#[pub]
# Check if JSON module can read
# Usage: json_ready -> returns 0 if it can, 1 if not
json_ready() {
    [ "$_JSON_READY" = "1" ]
}

#[pub]
# Get JSON module error (if not ready), or the note that it only reads
# Usage: json_error -> prints error message
json_error() {
    echo "$_JSON_ERROR"
}

#[pub]
# Get which JSON implementation is being used
# Usage: json_impl -> "jq" | "python" | "perl" | "bash" | ""
json_impl() {
    echo "$_JSON_IMPL"
}
