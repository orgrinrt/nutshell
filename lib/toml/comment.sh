#!/usr/bin/env bash
# =============================================================================
# nutshell/toml/comment.sh - The comment that belongs to a key
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The reader records the lines each `key = value` sits on, and what follows its
# value on the last of them, so the comment after a value is already known and
# the comments directly above its first line are the lines before it. There is
# no scanner here: a line is a comment of its own where it starts with `#` and
# no value the reader recorded spans it, which is how the last line of a
# multi-line string is told from a comment.

[ -n "${_NUTSHELL_TOML_COMMENT_SH:-}" ] && return 0
_NUTSHELL_TOML_COMMENT_SH=1

use super::toml super::toml::impl::bash_path

_TOML_RE_COMMENT='^[[:blank:]]*#(.*)$'

# _tm_inside <line> -> rc 0 where a value the reader recorded spans the line
# past its first, so that the line is the value's and not a comment
_tm_inside() {
    local IFS=$' \t\n'
    local k a b
    for k in "${!_TOML_W[@]}"; do
        read -r a b _ <<< "${_TOML_W[$k]}"
        (( $1 > a && $1 <= b )) && return 0
    done
    return 1
}

#[pub]
# Print the comment of a key: the comment lines directly above it, one per
# line, then the comment after its value.
#
# Each comes without its `#` and with the blanks around it trimmed. A comment
# parted from the key by a blank line is not the key's, nor is one above a table
# header. A key inside an inline table, a table and a key that is not there have
# no comment here; the path reaches a row of an array of tables, `row.0.id`.
# Returns 1 where there is no comment, 2 where the file is not TOML.
# Usage: toml_comment "file.toml" "section.key" -> prints the comment text, one line each
toml_comment() {
    local IFS=$' \t\n'
    local file="${1:-}" path="${2:-}" first rest ln line t
    local -a lines above=() out=()
    [[ -n "$file" && -n "$path" ]] || return 1
    _toml_open "$file" || return $?
    _toml_path_split "$path" || return 1
    _toml_lookup || return 1
    [[ -n "${_TOML_W[$_tl_node]-}" ]] || return 1
    read -r first rest <<< "${_TOML_W[$_tl_node]}"
    mapfile -t lines < "$file"
    for (( ln = first - 1; ln >= 0; ln-- )); do
        line="${lines[ln]%$'\r'}"
        [[ "$line" =~ $_TOML_RE_COMMENT ]] && ! _tm_inside "$ln" || break
        above=("$line" "${above[@]}")
    done
    for line in "${above[@]}" "${_TOML_C[$_tl_node]}"; do
        [[ "$line" =~ ^[[:blank:]]*#?(.*)$ ]] || continue
        t="${BASH_REMATCH[1]}"
        t="${t#"${t%%[![:space:]]*}"}"
        t="${t%"${t##*[![:space:]]}"}"
        [[ -n "$t" ]] && out+=("$t")
    done
    (( ${#out[@]} )) || return 1
    printf '%s\n' "${out[@]}"
}
