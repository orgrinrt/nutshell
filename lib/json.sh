#!/usr/bin/env bash
# =============================================================================
# nutshell/core/json.sh - JSON parsing and manipulation
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on deps.sh for tool detection, at the first call that
# needs a tool
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
# A plain path of a document no longer than `_JSON_FLOOR_MAX` bytes and
# `_JSON_FLOOR_NODES` values is answered by the reader in bash first, with jq
# or another tool behind it, so a hook that reads one field of its payload on
# every tool call runs no tool at all. The reader answers only where its text
# is the tool's to the byte, and hands the rest on (`_json_floor` in
# `json/impl/bash.sh`). Past either limit the tool is the faster. Setting
# `_JSON_IMPL` to a backend sends every call to it.
#
# `use json` loads the readers and nothing else: `deps`, the tool backends, the
# builders and `json_query` load at the first call that needs them. Inside a
# `$(...)` that load is the subshell's and goes with it.
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
# Status: 0 found, 1 not there or not JSON, 2 nothing here can do it. A tool's
# own status never gets out. One text and one status whoever reads, for
# `json_get`, `json_has`, `json_keys`, `json_type`, `json_length` and
# `json_valid`, held against every backend by `tests/json_contract_test.sh`:
#
#   - a document is exactly one JSON value; text after it, a second value and
#     nothing at all are not JSON, and neither is a literal JSON does not have
#     (`01`, `.5`, `1.`, `+1`, `NaN`)
#   - a segment of digits indexes an array and is a plain key on an object,
#     `a.0` on `{"a":{"0":1}}` included; any other segment on an array is not
#     there, so `a.-1`, `a.+1` and `a.1e0` are status 1; leading zeros count
#     (`a.01` is index 1)
#   - a number is printed as the document wrote it, alone or inside a
#     container: `1e3` is `1e3`, `1.50` is `1.50`; a string is printed bare
#   - `json_length` is the count of an array or object, the characters of a
#     string and 0 for null; a number or a boolean has none, status 1
#   - an empty segment is dropped, so a path of nothing but those is the
#     whole document, and an empty key cannot be reached
#   - outside it: a string holding a NUL or a lone surrogate, which jq and perl
#     repair or refuse and python and the reader in bash keep; and a number
#     jq or perl would respell, where the reader in bash that prints it as
#     written is absent (a shell without bash) or cannot hold the document
#     (nested past 400 levels), which comes back in the tool's spelling, `1e3`
#     as `1E+3` under jq and `1000` under perl, and not as nothing
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

# Declared, not sourced by path, so the module-contract check sees them. The
# path language is the toml reader's, and its splitter is loaded as it is
# rather than copied; the reader in bash is the floor. Both need bash, so a
# shell without it reads through a tool. `deps`, the backends, `json::build`
# and `json::query` are `use`d where they are first needed.
if [ -n "${BASH_VERSION:-}" ]; then
    use super::toml::impl::bash_path super::json::impl::bash
fi

# What joins the segments of a path on their way to a backend.
# A capture under a POSIX shell and the quoting bash has under bash, as in
# `json::build`.
if [ -n "${BASH_VERSION:-}" ]; then
    eval "_JSON_US=\$'\\037'"
else
    _JSON_US="$(printf '\037.')"; _JSON_US="${_JSON_US%.}"
fi

# The longest document the floor answers for a tool, in bytes, and the most
# values it parses before handing the question to the tool. The reader in bash
# costs about 90us a value and a little a byte, and jq two runs of about 4.5ms:
# measured on this machine, the floor is the faster up to about 32 KB of one
# long string and up to about 100 values, and the budget sits below that so a
# document that passes it has cost less than one run of jq before it goes to
# one. `benches/start-cost` prices the hook path that this is for.
: "${_JSON_FLOOR_MAX:=32768}"
: "${_JSON_FLOOR_NODES:=64}"

# -----------------------------------------------------------------------------
# Backends
# -----------------------------------------------------------------------------
#
# Interchangeable implementations of the same operations, one per tool, in
# `json/impl/`. The one in bash needs no tool and only reads.
#
# `_JSON_IMPL` is a backend a caller (or a test) named, and empty means the one
# picked from what `deps` finds, kept in `_JSON_TOOL`. A backend is loaded the
# first time a call goes to it, named or picked, so a test can still move
# `_JSON_IMPL` and get the implementation it named.

_JSON_READY=0
_JSON_ERROR=""
_JSON_IMPL="${_JSON_IMPL:-}"
_JSON_TOOL=""
_JSON_PICKED=0

#[pub]
# Pick the backend again, from what `deps` knows now, and forget one a caller
# named. Run at the first call that needs a tool, and after `deps_forget` when a
# tool has come or gone.
# Order: jq, python, perl, then bash, which only reads.
# Usage: json_detect
json_detect() {
    _JSON_IMPL=""
    _JSON_PICKED=1
    _JSON_READY=1
    _JSON_ERROR=""
    use deps || return 1
    deps_on_reset _json_reset
    if deps_has jq; then
        _JSON_TOOL="jq"
    elif deps_has python3 || deps_has python; then
        _JSON_TOOL="python"
    elif deps_has perl; then
        _JSON_TOOL="perl"
    elif type _json_get_bash >/dev/null 2>&1; then
        _JSON_TOOL="bash"
        _JSON_ERROR="No jq, python or perl: reading only"
    else
        _JSON_READY=0
        _JSON_TOOL=""
        _JSON_ERROR="No JSON tool available (need jq, python, perl or bash)"
    fi
}

# _json_reset -> the pick dropped, made again at the next call that needs it
# Registered with `deps` when a pick is made, so a hide or a forget reaches it.
_json_reset() { _JSON_PICKED=0; }

# _json_now -> `_JSON_NOW`, the backend this call goes to, loaded; rc 1 where
# there is none
_json_now() {
    [ "$_JSON_PICKED" = "1" ] || json_detect
    _JSON_NOW="${_JSON_IMPL:-$_JSON_TOOL}"
    case "$_JSON_NOW" in
        # Asked of `deps` first, since a backend reads its tool's path as it
        # loads, and a named one may be one the pick never asked about.
        jq)     deps_has jq && use super::json::impl::jq ;;
        python) { deps_has python3 || deps_has python; } && use super::json::impl::python ;;
        perl)   deps_has perl && use super::json::impl::perl ;;
        bash)   type _json_get_bash >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
}

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
    _json_now && [ "$_JSON_READY" = "1" ] && return 0
    echo "${1}: ${_JSON_ERROR:-no backend ${_JSON_NOW:-}}" >&2
    return 1
}

# _json_needs_tool <name> -> status 2 with the reason when the backend this call
# goes to cannot write, which is the one in bash.
_json_needs_tool() {
    _json_now && case "$_JSON_NOW" in
        jq|python|perl) return 0 ;;
    esac
    echo "${1}: needs jq, python or perl, and this machine has none" >&2
    return 2
}

# _json_read <op> <name> <json> <path> -> what the op prints, from the floor
# where it answers and from the backend otherwise
_json_read() {
    local op="$1" name="$2" json="${3:-}" rc
    [ -z "$json" ] && return 1
    _json_segs "${4:-}" || return 2
    if [ -z "$_JSON_IMPL" ] && [ "${#json}" -le "$_JSON_FLOOR_MAX" ] \
        && type _json_floor >/dev/null 2>&1; then
        rc=0; _json_floor "$op" "$json" "$_js_out" || rc=$?
        [ "$rc" -le 1 ] && return "$rc"
    fi
    _json_ready_for "$name" || return 1
    rc=0
    "_json_${op}_${_JSON_NOW}" "$json" "$_js_out" || rc=$?
    [ "$rc" -eq 7 ] || return "$rc"
    # A backend ends a get with 7 where it would print a number, or a container
    # holding one, in a spelling of its own, `1e3` as `1E+3` or `1000`, and the
    # document's is the answer: the reader in bash has it to the byte. Where it
    # cannot answer, a shell without it or a document nested deeper than it
    # holds, the backend's spelling is, and a status of 0 beats none.
    if type _json_get_bash >/dev/null 2>&1 && _json_get_bash "$json" "$_js_out"; then
        return 0
    fi
    "_json_getn_${_JSON_NOW}" "$json" "$_js_out"
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
# Returns: The value at the path, a number as the document wrote it; status 1
# when there is none, or the document is not one JSON value
json_get() { _json_read get json_get "$@"; }

#[pub]
# Get all keys at a path in JSON
# Usage: json_keys '{"a":1,"b":2}' -> prints "a" and "b" on separate lines
# Usage: json_keys '{"x":{"y":1}}' "x" -> prints "y"
# Returns: Keys, one per line; status 1 where there is nothing at the path or it
# holds a scalar, on every backend
json_keys() { _json_read keys json_keys "$@"; }

#[pub]
# Check if JSON is valid
# Usage: json_valid '{"foo":"bar"}' -> returns 0 (valid)
# Usage: json_valid 'not json' -> returns 1 (invalid)
# Returns: 0 if valid, 1 if invalid
json_valid() {
    local json="${1:-}"
    [ -z "$json" ] && return 1
    _json_now || return 1
    [ "$_JSON_READY" != "1" ] && return 1
    "_json_valid_${_JSON_NOW}" "$json"
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
json_type() { _json_read type json_type "$@"; }

#[pub]
# Get the length of a JSON array, object or string
# Usage: json_length '[1,2,3]' -> "3"
# Usage: json_length '{"a":1,"b":2}' -> "2"
# Usage: json_length '"abc"' -> "3"
# Usage: json_length null -> "0"
# Returns: The count of an array or object, the characters of a string, 0 for
# null; status 1 for a number or a boolean, which have none
json_length() { _json_read length json_length "$@"; }

#[pub]
# Check if a path exists in JSON
# Usage: json_has '{"a":{"b":1}}' "a.b" -> returns 0 (exists)
# Usage: json_has '{"a":1}' "b" -> returns 1 (not found)
# Returns: 0 if path exists and is neither null nor empty, 1 otherwise
json_has() {
    local json="${1:-}" path="${2:-}" result rc
    [ -z "$json" ] && return 1
    if [ -z "$_JSON_IMPL" ] && [ "${#json}" -le "$_JSON_FLOOR_MAX" ] \
        && type _json_floor >/dev/null 2>&1 && _json_segs "$path" 2>/dev/null; then
        rc=0; _json_floor has "$json" "$_js_out" || rc=$?
        [ "$rc" -le 1 ] && return "$rc"
    fi
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
    "_json_set_${_JSON_NOW}" "$json" "$_js_out" "$value"
}

#[pub]
# Delete a key from JSON
# Usage: json_delete '{"a":1,"b":2}' "a" -> '{"b":2}'
# Returns: JSON with key removed; status 2 with none of jq, python or perl
json_delete() {
    local json="${1:-}"
    _json_needs_tool json_delete || return 2
    _json_segs "${2:-}" || return 2
    "_json_delete_${_JSON_NOW}" "$json" "$_js_out"
}

#[pub]
# Merge two JSON objects (second overwrites first for conflicts)
# Usage: json_merge '{"a":1}' '{"b":2}' -> '{"a":1,"b":2}'
# Returns: Merged JSON object; status 2 with none of jq, python or perl
json_merge() {
    local json1="${1:-\{\}}" json2="${2:-\{\}}"
    _json_needs_tool json_merge || return 2
    "_json_merge_${_JSON_NOW}" "$json1" "$json2"
}

#[pub]
# Pretty print JSON with indentation
# Usage: json_pretty '{"a":1,"b":2}' -> prints formatted JSON
# Returns: Pretty-printed JSON; status 2 with none of jq, python or perl
json_pretty() {
    local json="${1:-}"
    _json_needs_tool json_pretty || return 2
    [ -z "$json" ] && return 1
    "_json_pretty_${_JSON_NOW}" "$json"
}

#[pub]
# Compact JSON (remove whitespace)
# Usage: json_compact '{ "a": 1, "b": 2 }' -> '{"a":1,"b":2}'
# Returns: Compact JSON on single line; status 2 with none of jq, python or perl
json_compact() {
    local json="${1:-}"
    _json_needs_tool json_compact || return 2
    [ -z "$json" ] && return 1
    "_json_compact_${_JSON_NOW}" "$json"
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

#[pub]
# Create a simple JSON object from key-value pairs, with no tool
# Usage: json_object "key1" "value1" "key2" "value2" -> '{"key1":"value1","key2":"value2"}'
# Returns: JSON object
json_object() {
    use super::json::build || return 1
    _json_object_build "$@"
}

#[pub]
# Create a JSON array from values, with no tool
# Usage: json_array "a" "b" "c" -> '["a","b","c"]'
# Returns: JSON array
json_array() {
    use super::json::build || return 1
    _json_array_build "$@"
}

#[pub]
# Run a jq program over a document, through jq, gojq or jaq, whichever `deps`
# finds first that has every option the call uses. Strings come back bare and
# everything else compact, so `json_query '.a | length' "$doc"` prints `3`.
# The document is the operand after the filter, or stdin when there is none.
# Options, before or after the filter; `--` ends them, so a filter or a
# document that starts with `-` follows a `--`:
#   -r  strings bare (already the default)    --json  strings as JSON text
#   -j  join output, no newline after each    -c      compact (the default)
#   -n  null input        -s  slurp        -R  raw input
#   -e  the status follows the last result (jq's: 1 false or null, 4 none)
#   --arg <name> <text>   --argjson <name> <json>
#   --slurpfile <name> <file>   --rawfile <name> <file>
#   --args  every operand after the filter is a string in `$ARGS.positional`,
#           and the document is stdin
#   and the long forms --raw-output --join-output --compact-output
#   --null-input --slurp --raw-input --exit-status
# Usage: json_query '.items[] | .name' "$json"
# Usage: curl -s "$url" | json_query '.total'
# Usage: json_query -n --arg k "$key" --argjson v "$val" '{($k): $v}'
# Usage: json_query -n --args '$ARGS.positional' "$a" "$b"
# Returns: what the program printed. Status 2 is a refusal: no jq family tool
# is here, or none that has an option the call uses (the refusal names it), an
# option none of them has, or more operands than a filter and a document. 1
# for no filter, and for a query the tool failed, its own status 2 included
# (a file `--slurpfile` cannot open); otherwise the tool's status.
json_query() {
    use super::json::query || return 2
    _json_query_run "$@"
}

# -----------------------------------------------------------------------------
# Module Status Functions
# -----------------------------------------------------------------------------

#[pub]
# Check if JSON module can read
# Usage: json_ready -> returns 0 if it can, 1 if not
json_ready() {
    _json_now
    [ "$_JSON_READY" = "1" ]
}

#[pub]
# Get JSON module error (if not ready), or the note that it only reads
# Usage: json_error -> prints error message
json_error() {
    _json_now
    echo "$_JSON_ERROR"
}

#[pub]
# Get which JSON implementation a call that needs a tool goes to
# Usage: json_impl -> "jq" | "python" | "perl" | "bash" | ""
json_impl() {
    _json_now
    echo "$_JSON_NOW"
}
