#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/json/impl/jq.sh - JSON through jq
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# One of three interchangeable backends behind `lib/json.sh`, which dispatches
# on `_JSON_IMPL`. Nothing here is called directly; the module's public
# functions pick a backend and forward.
#
# Sourced by json.sh when jq is present. All available backends are loaded
# rather than only the selected one, so a caller (or a test) can move
# `_JSON_IMPL` and get the implementation it named.
#
# `-c` and `-S` on everything that returns a document. Without `-c` jq formats
# where python and perl print compact, and `-S` sorts object keys, which is the
# only order all three can produce: a perl hash does not preserve insertion
# order and JSON::PP cannot invent one.
# =============================================================================

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded: under a POSIX shell `nut_once` is not found, the `|| return
# 0` returns from the whole file, and the module then defines nothing while
# reporting success.
[ -n "${_NUTSHELL_JSON_IMPL_JQ_SH:-}" ] && return 0
_NUTSHELL_JSON_IMPL_JQ_SH=1

use string

# _jq_lit <segment> -> `_jq_e`, the segment as a jq string literal
# Backslash first, or the quote's backslash is escaped again.
_jq_lit() {
    _jq_e="$1"
    str_replace "$_jq_e" '\' '\\' _jq_e
    str_replace "$_jq_e" '"' '\"' _jq_e
    _jq_e="\"${_jq_e}\""
}

# _jq_path <segments> -> a jq path expression
#
# The segments of a path joined by the unit separator, split by the caller
# (`json.sh`), so a key that holds a dot is one segment. Every function here
# used to build its own by putting a dot in front of the whole path, which is
# wrong for any segment that is a number: `.1` is not the second element of an
# array, it is the number 0.1, so `json_get '[10,20]' 1` answered `0.1`.
# Bracket form for both kinds, and a name is quoted so a key holding a dash or
# a space stays one segment.
_jq_path() {
    local rest="${1:-}" expr="." seg
    while [ -n "$rest" ]; do
        case "$rest" in
            *"$_JSON_US"*) seg="${rest%%"$_JSON_US"*}"; rest="${rest#*"$_JSON_US"}" ;;
            *)             seg="$rest"; rest="" ;;
        esac
        [ -z "$seg" ] && continue
        case "$seg" in
            *[!0-9]*) _jq_lit "$seg"; expr="${expr}[${_jq_e}]" ;;
            *)        expr="${expr}[${seg}]" ;;
        esac
    done
    printf '%s' "$expr"
}

# Whether a jq value is a number rather than a string, so `_json_set_jq` knows
# whether to quote it. Written as `case` because the shape it recognises is a
# glob's worth of work and `[[ =~ ]]` is bash.
_jq_is_number() {
    local n="${1:-}"
    case "$n" in -*) n="${n#-}" ;; esac
    case "$n" in
        '' | *[!0-9.]* ) return 1 ;;   # empty, or a character that is neither
        .* | *. )        return 1 ;;   # a dot at either end
    esac
    case "${n#*.}" in
        *.* ) return 1 ;;              # more than one dot
    esac
    return 0
}

# The reading half of this file, one jq run per call.
#
# The document is read as text and parsed by `fromjson`, which takes exactly one
# value: trailing text, a second value and nothing at all are all "not JSON".
# jq's own reader is more generous than JSON is (`01`, `.5`, `1.`, `+1`, `NaN`
# and `Infinity` are all numbers to it), so every token outside a string is
# checked first against what JSON allows.
#
# A path is walked here, in jq, by what each node is: a segment of digits
# indexes an array and is just a key on an object, `"0"` included, and any other
# segment on an array is not there. Building the walk as `.a[0]` made a digit
# key on an object an error, and a path that leads nowhere an exit of 5, which
# is jq's own and outside the status this module gives. `halt_error` ends the
# run with the status chosen: 1 is "not there", 7 is "a number", which
# `_json_get_jq` hands to the reader in bash so it prints as the document wrote
# it.
_JQ_READ_DEFS='
def strict:
    gsub("\"(?:[^\"\\\\]|\\\\.)*\""; "0")
    | [scan("[^\\s\\[\\]{},:]+")]
    | all(.[]; test("^(?:-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|true|false|null)$"));
def step($s):
    if type == "object" then (if has($s) then .[$s] else empty end)
    elif type == "array" then
        (if ($s | test("^[0-9]+\\z")) then
            (($s | tonumber) as $i | if $i < length then .[$i] else empty end)
         else empty end)
    else empty end;
def at($p): if ($p | length) == 0 then . else (step($p[0]) | at($p[1:])) end;
def nope: "" | halt_error(1);
def doc: if strict then (try fromjson catch nope) else nope end;
def read(f):
    ([doc | at($segs | split("\u001f") | map(select(. != "")))]) as $r
    | if ($r | length) == 0 then nope else $r[0] | f end;
'

# _jq_read <json> <segments> <program over the node, in `f`> -> what it prints;
# status 1 where the document is not one JSON value, the path leads nowhere or
# the program ends the run, 7 where it did so for a number
_jq_read() {
    local rc=0
    printf '%s\n' "$1" | "${_TOOL_PATH_jq}" -R -s -c -S -r --arg segs "${2:-}" \
        "${_JQ_READ_DEFS} read($3)" 2>/dev/null || rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 7 ] || rc=1
    return "$rc"
}

# A number is printed as the document wrote it, which jq does not do: it prints
# `1e3` as `1E+3`, in a container as much as alone. So jq ends the run with 7 for
# a number, and for a container with a fraction, an exponent or sixteen digits
# in it (the text of a string that looks like one is only a slower answer), and
# `json.sh` has the reader in bash answer instead; `_json_getn_jq` is what jq
# itself prints, for a shell without that reader.
_json_get_jq() {
    _jq_read "${1:-}" "${2:-}" 'if type == "number" then ("" | halt_error(7))
        elif (type == "array" or type == "object") and (tojson | test("[0-9][.eE]|[0-9]{16}"))
            then ("" | halt_error(7))
        else . end'
}

_json_getn_jq() { _jq_read "${1:-}" "${2:-}" '.'; }

# Whether the value is already a JSON literal: a keyword, a number, an array or
# an object. Everything else is a string.
_jq_is_json_literal() {
    case "${1:-}" in
        true | false | null ) return 0 ;;
        '['* | '{'* )         return 0 ;;
    esac
    _jq_is_number "${1:-}"
}

_json_set_jq() {
    local json="${1:-}" path="${2:-}" value="${3:-}" expr
    expr="$(_jq_path "$path")"

    # A value that is already JSON goes in unquoted; anything else is a string
    # and goes through `--arg` so jq quotes it.
    if _jq_is_json_literal "$value"; then
        printf '%s\n' "$json" | "${_TOOL_PATH_jq}" -c -S "$expr = $value" 2>/dev/null
    else
        printf '%s\n' "$json" | "${_TOOL_PATH_jq}" -c -S --arg v "$value" "$expr = \$v" 2>/dev/null
    fi
}

_json_keys_jq() {
    # Status 1 where there is no such path or it holds a scalar, as the other
    # readers give.
    _jq_read "${1:-}" "${2:-}" 'if type == "array" then range(length) elif type == "object" then keys[] else nope end'
}

_json_valid_jq() {
    # One value and no more, and only what JSON allows, as the other readers
    # have it: `-e` alone says `null` is false and reads a second value as
    # another document.
    printf '%s\n' "${1:-}" | "${_TOOL_PATH_jq}" -R -s -e "${_JQ_READ_DEFS} strict and (try (fromjson | true) catch false)" >/dev/null 2>&1 || return 1
}

_json_pretty_jq() {
    local json="${1:-}"
    printf '%s\n' "$json" | "${_TOOL_PATH_jq}" -S '.' 2>/dev/null
}

_json_compact_jq() {
    local json="${1:-}"
    printf '%s\n' "$json" | "${_TOOL_PATH_jq}" -c -S '.' 2>/dev/null
}

_json_type_jq() {
    _jq_read "${1:-}" "${2:-}" 'type'
}

# A string is counted in characters, null is empty, and a number or a boolean has
# no length: status 1, as the reader in bash gives. jq would count the size of a
# number and refuse a boolean.
_json_length_jq() {
    _jq_read "${1:-}" "${2:-}" 'if type == "array" or type == "object" or type == "string" then length elif type == "null" then 0 else nope end'
}

# `*` recurses into objects where python's `update` and perl's slice assignment
# replace them, so one call built a different document depending on the tool.
# `+` is the shallow one: the right operand replaces a key rather than merging
# into it.
_json_merge_jq() {
    local json1="$1" json2="$2"
    printf '%s\n' "$json1" | "${_TOOL_PATH_jq}" -c -S ". + $json2" 2>/dev/null
}

# `del` printed its result formatted while python and perl printed it compact.
_json_delete_jq() {
    local json="$1" path="$2" expr
    expr="$(_jq_path "$path")"
    printf '%s\n' "$json" | "${_TOOL_PATH_jq}" -c -S "del($expr)" 2>/dev/null
}
