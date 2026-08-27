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
# Usage: nut_defined_at <file> <function> -> prints a line number
nut_defined_at() {
    local at="${_NUT_FILE_AT["${1}:${2}"]:-}"
    [[ -n "$at" ]] || return 1
    printf '%s' "$at"
}

#[pub]
# Where a function's body ends: the first line that closes it at column one, or
# closes it alone on its own line. The same heuristic the checks used, without
# the `tail | grep | head | cut` it took four processes to express.
# Usage: nut_ends_at <file> <function> -> prints a line number
nut_ends_at() {
    local file="$1" start end n line
    start="$(nut_defined_at "$file" "$2")" || return 1
    n="${_NUT_FILE_N[$file]:-0}"
    for (( end = start + 1; end <= n; end++ )); do
        line="${_NUT_FILE_BODY["${file}:${end}"]}"
        [[ "$line" == "}" ]] && { printf '%s' "$end"; return 0; }
        [[ "$line" =~ ^[[:space:]]*\}[[:space:]]*$ ]] && { printf '%s' "$end"; return 0; }
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
    local file="$1" fn="$2" out="$3" start end i line
    [[ "$out" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
    eval "$out=()"
    start="$(nut_defined_at "$file" "$fn")" || return 1
    end="$(nut_ends_at "$file" "$fn")" || return 1
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

