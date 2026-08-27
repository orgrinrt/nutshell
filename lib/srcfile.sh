#!/usr/bin/env bash
# =============================================================================
# nutshell/srcfile - A source file, read once, asked many times
# =============================================================================
# Part of nutshell. https://github.com/orgrinrt/nutshell
#
# Every checker reads the same files and asks the same four questions about
# them: where is this function, where does it end, what is in its body, what is
# on line N. Each of those used to be a pipeline: `grep | head | cut` for a
# definition, `tail | grep | head | cut` for its end, a seven-stage `grep -v`
# chain for a body. Thousands of processes per run, and every checker starting
# again from nothing.
#
# Usage:
#   use srcfile
#
#   nut_load_file lib/log.sh          # once, in the shell that loops
#   nut_defined_at lib/log.sh log_info
#   nut_body_of    lib/log.sh log_info BODY
# =============================================================================

[[ -n "${_NUTSHELL_SRCFILE_SH:-}" ]] && return 0
readonly _NUTSHELL_SRCFILE_SH=1

# For `ATTR_DEFINES_PATTERN`: one answer about what a definition is.
use attr

declare -gA _NUT_FILE_BODY=()
declare -gA _NUT_FILE_AT=()
declare -gA _NUT_FILE_N=()

#[pub]
# Read a file into the cache, once. Later calls for it do nothing.
# Usage: nut_load_file <file>
nut_load_file() {
    local file="${1:-}"
    [[ -n "${_NUT_FILE_N[$file]:-}" ]] && return 0
    [[ -r "$file" ]] || return 1

    local -a lines=()
    if [[ "$(type -t mapfile)" == "builtin" ]]; then
        mapfile -t lines < "$file" 2>/dev/null || return 1
    else
        local l
        while IFS= read -r l || [[ -n "$l" ]]; do lines+=("$l"); done < "$file" || return 1
    fi

    local i line name
    for (( i = 0; i < ${#lines[@]}; i++ )); do
        line="${lines[$i]}"
        _NUT_FILE_BODY["${file}:$((i + 1))"]="$line"
        # The shared pattern, so a definition means the same thing here as it
        # does to `attr`. The two had drifted: this one missed
        # `function name {` and that one missed both a hyphen and a space
        # before the parentheses.
        if [[ "$line" =~ $ATTR_DEFINES_PATTERN ]]; then
            name="${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
            [[ -n "${_NUT_FILE_AT["${file}:${name}"]:-}" ]] \
                || _NUT_FILE_AT["${file}:${name}"]=$((i + 1))
        fi
    done
    _NUT_FILE_N[$file]="${#lines[@]}"
    return 0
}

#[pub]
# One line of a loaded file, by number. Nothing when it is not there.
# Usage: nut_file_line <file> <n> -> prints the line
nut_file_line() { printf '%s' "${_NUT_FILE_BODY["${1}:${2}"]:-}"; }

#[pub]
# How many lines a loaded file has.
# Usage: nut_file_lines <file> -> prints a count
nut_file_lines() { printf '%s' "${_NUT_FILE_N[${1}]:-0}"; }

#[pub]
# The line a function is defined on, or nothing.
#
# Name a variable and the answer goes there instead of to stdout. The lookup
# itself is one array read; read through a command substitution it costs a
# fork, which is a thousand times the read. On a checker asking this of every
# function in the library it was most of what the checker cost.
# Usage: nut_defined_at <file> <function> [out-name] -> prints a line number
nut_defined_at() {
    # Every local here is prefixed, because the out-name is written with
    # `printf -v` and bash scopes dynamically: a local called `at` would
    # shadow a caller asking for its own `at` and the answer would land in
    # this frame and die with it. The caller cannot see that happen.
    local __nd_at="${_NUT_FILE_AT["${1}:${2}"]:-}"
    [[ -n "$__nd_at" ]] || return 1
    if [[ -n "${3:-}" ]]; then
        [[ "$3" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
        printf -v "$3" '%s' "$__nd_at"
        return 0
    fi
    printf '%s' "$__nd_at"
}

#[pub]
# Where a function's body ends: the first line that closes it at column one, or
# closes it alone on its own line. The same heuristic the checks used, without
# the `tail | grep | head | cut` it took four processes to express.
# Name a variable and the answer goes there instead of to stdout, as with
# `nut_defined_at`.
# Usage: nut_ends_at <file> <function> [out-name] -> prints a line number
nut_ends_at() {
    # Prefixed for the same reason as `nut_defined_at`, and it is not
    # hypothetical here: the first version used `end`, and `nut_body_of` asks
    # for its answer in a variable called `end`. The write landed in this
    # frame, the caller read its own untouched local, and under `set -u` that
    # surfaced as an unbound variable three tests away from the cause.
    local __ne_file="$1" __ne_out="${3:-}" __ne_start __ne_end __ne_n __ne_line
    [[ -z "$__ne_out" || "$__ne_out" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
    nut_defined_at "$__ne_file" "$2" __ne_start || return 1
    __ne_n="${_NUT_FILE_N[$__ne_file]:-0}"
    for (( __ne_end = __ne_start + 1; __ne_end <= __ne_n; __ne_end++ )); do
        __ne_line="${_NUT_FILE_BODY["${__ne_file}:${__ne_end}"]}"
        if [[ "$__ne_line" == "}" || "$__ne_line" =~ ^[[:space:]]*\}[[:space:]]*$ ]]; then
            if [[ -n "$__ne_out" ]]; then
                printf -v "$__ne_out" '%s' "$__ne_end"
            else
                printf '%s' "$__ne_end"
            fi
            return 0
        fi
    done
    return 1
}

#[pub]
# The lines of a function's body that carry something.
#
# Comments, blanks, bare declarations and a bare `return` are dropped, which is
# what a seven-stage `grep -v` chain was doing per function.
# Usage: nut_body_of <file> <function> <array-name>
nut_body_of() {
    local file="$1" fn="$2" out="$3" start=0 end=0 i line
    [[ "$out" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
    eval "$out=()"
    nut_defined_at "$file" "$fn" start || return 1
    nut_ends_at "$file" "$fn" end || return 1
    for (( i = start + 1; i < end; i++ )); do
        line="${_NUT_FILE_BODY["${file}:${i}"]}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*(local|readonly)[[:space:]] ]] && continue
        [[ "$line" =~ ^[[:space:]]*return[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*return[[:space:]]+\$\?[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*$ ]] && continue
        eval "$out+=(\"\$line\")"
    done
    return 0
}

