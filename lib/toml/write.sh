#!/usr/bin/env bash
# =============================================================================
# nutshell/toml/write.sh - Changing a TOML file without rewriting it
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Reading TOML and editing TOML are different jobs and they live apart, but
# there is one grammar. The writer asks the reader's tree where a key sits, in
# lines, and edits those lines and nothing else. Where the tree cannot vouch
# for a key being on lines of its own, the edit is refused with rc 2.
# =============================================================================

# A guard of its own rather than `nut_once`, for the same reason as every file
# of the module.
[ -n "${_NUTSHELL_TOML_WRITE_SH:-}" ] && return 0
_NUTSHELL_TOML_WRITE_SH=1

# `str_replace` with an out-name, for the escaping below. This file carried its
# own copy of that loop, as did `json.sh` and `extern.sh`; one of the three then
# diverged and shipped an injection hole that the other two did not have.
use string super::toml super::toml::impl::bash_path

# The control characters a basic string escapes, as themselves.
_TW_NL=$'\n'
_TW_CR=$'\r'
_TW_TAB=$'\t'
_TW_BS=$'\b'
_TW_FF=$'\f'

# _tw_place <file> <key> <verb> -> where the key goes, or rc 2 and why
#
# Reads the file through the reader and walks the key's path in its tree. Sets
# `_tw_node`, the key's node, `_tw_parent`, the table it goes in, `_tw_leaf`,
# its last segment as TOML spells it, and `_tw_head`, the header to open when
# the table has no part of the file to add to. The key is not there when
# `_tw_node` is empty. rc 1 for a key the path language cannot
# read.
#
# Refused, because one line cannot change it without breaking the file:
#   a key inside an array of tables, where a header names every element at
#     once and a line names one;
#   a key inside an inline table, which is one value on one line;
#   a key a dotted key made, or one in a table a dotted key made, which is not
#     on a line of its own and whose table a header would define twice;
#   a key whose path runs into a value or an array.
_tw_place() {
    local file="$1" key="$2" verb="$3" node=R seg t i last shown="" whole=""
    _toml_open "$file" || return $?
    _toml_path_split "$key" || return 1
    last=$(( ${#_tp_pseg[@]} - 1 ))
    for (( i = 0; i < last; i++ )); do
        _toml_seg_show "${_tp_pseg[i]}"; whole+="${whole:+.}${_ts_out}"
    done
    # Down the tree as far as it goes. Where it stops, the rest is new.
    for (( i = 0; i < last; i++ )); do
        seg="$node$_TOML_US${_tp_pseg[i]}"
        t="${_TOML_T[$seg]-}"
        [[ -n "$t" ]] || break
        _toml_seg_show "${_tp_pseg[i]}"; shown+="${shown:+.}${_ts_out}"
        case "$t" in
            table) node="$seg" ;;
            aot)   _tw_deny "it is inside the array of tables [[$shown]]"; return 2 ;;
            *)     _tw_deny "$shown is a value, not a table"; return 2 ;;
        esac
    done
    if [[ "${_TOML_F[$node]-}" == *X* ]]; then
        _tw_deny "it is inside the inline table $shown"; return 2
    fi
    _tw_head="" _tw_parent="$node"
    _toml_seg_show "${_tp_pseg[last]}"; _tw_leaf="$_ts_out"
    _tw_node=""
    if (( i < last )); then
        _tw_head="$whole"
        return 0
    fi
    if [[ "$node" != R && "${_TOML_F[$node]}" != *[hi]* ]]; then
        _tw_deny "a dotted key, $shown, defines it or a table above it"; return 2
    fi
    [[ "$node" == R || -n "${_TOML_E[$node]+x}" ]] || _tw_head="$whole"
    seg="$node$_TOML_US${_tp_pseg[last]}"
    [[ -n "${_TOML_T[$seg]-}" ]] || return 0
    case "${_TOML_W[$seg]-}" in
        '')    _tw_deny "it is a table, not a value"; return 2 ;;
        *' '1) _tw_node="$seg" ;;
        *)     _tw_deny "a dotted key defines it, not a line of its own"; return 2 ;;
    esac
}

_tw_deny() {
    printf 'toml: %s: cannot %s %s: %s\n' "$file" "$verb" "$key" "$1" >&2
}

# _tw_out <file> -> `_tw_lines` written to the file, through a rename
#
# Renamed into place, so a reader never sees a half-written file and a crash
# partway leaves the original intact.
_tw_out() {
    local tmp
    tmp="$(mktemp "$1.XXXXXX")" || return 1
    if (( ${#_tw_lines[@]} )); then
        printf '%s\n' "${_tw_lines[@]}" > "$tmp" || { rm -f "$tmp"; return 1; }
    fi
    mv -f "$tmp" "$1" || { rm -f "$tmp"; return 1; }
}

# _tw_edit <first> <last> [line] -> `_tw_lines` with lines <first> to <last>
# swapped for the line, or dropped without one; <last> one before <first> puts
# the line in between. The new line ends in `\r` where the one before it does,
# and the file's BOM stays at the head of the file.
_tw_edit() {
    local a="$1" b="$2" new=("${@:3}") bom=$'\xef\xbb\xbf'
    if (( ${#new[@]} && b >= 0 )); then
        [[ "${_tw_lines[b]}" == *$'\r' ]] && new[0]+=$'\r'
    fi
    if (( a == 0 && ${#new[@]} )) && [[ "${_tw_lines[0]-}" == "$bom"* ]]; then
        _tw_lines[0]="${_tw_lines[0]#"$bom"}"
        new[0]="$bom${new[0]}"
    fi
    _tw_lines=("${_tw_lines[@]:0:a}" "${new[@]}" "${_tw_lines[@]:b+1}")
}

#[pub]
# Write a value, leaving the rest of the file as it was.
#
# Editing a config file is not the same as generating one. A person wrote the
# comments in it, chose the order, put a blank line where they wanted a pause,
# and a setter that rewrites the file from a parsed model throws all of that
# away the first time anything saves. So: find the line, change the line, and
# touch nothing else.
#
# The key is a path, the same as `toml_get` takes. A key that is there has its
# value replaced, over every line the value spans, and keeps its indent, its
# spelling and its comment. A key that is not there goes in after the last line
# of its table's part of the file, so a root key lands above the first header;
# a table with no part of its own gets a header at the end.
#
# Usage: toml_set "file.toml" "section.key" "value" -> returns 2 for a shape one line cannot change
toml_set() {
    local file="${1:-}" key="${2:-}" value="${3-}" verb=set written span e
    [[ -n "$file" && -n "$key" ]] || return 1
    [[ -f "$file" ]] || { : > "$file" 2>/dev/null || return 1; }
    _tw_place "$file" "$key" set || return $?
    written="$(_toml_write_value "$value")"
    mapfile -t _tw_lines < "$file"
    if [[ -n "$_tw_node" ]]; then
        read -r -a span <<< "${_TOML_W[$_tw_node]}"
        _tw_edit "${span[0]}" "${span[1]}" "${_TOML_P[$_tw_node]}${written}${_TOML_C[$_tw_node]}"
    elif [[ -z "$_tw_head" ]]; then
        e="${_TOML_E[$_tw_parent]}"
        _tw_edit $(( e + 1 )) "$e" "${_tw_leaf} = ${written}"
    else
        (( ${#_tw_lines[@]} )) && _tw_lines+=("")
        _tw_lines+=("[${_tw_head}]" "${_tw_leaf} = ${written}")
    fi
    _tw_out "$file"
}

# A value as TOML writes it.
#
# A number, a bool and an array go in bare; everything else is a basic string,
# and a basic string carries escapes. The five the reader decodes are the five
# encoded here: without them a value with a newline in it wrote a file that no
# longer parses at all, which loses every other key in it rather than the one
# being written.
_toml_write_value() {
    local v="$1" esc
    if [[ "$v" =~ ^-?[0-9]+$ || "$v" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
        printf '%s' "$v"; return 0
    fi
    case "$v" in
        true|false) printf '%s' "$v"; return 0 ;;
        "["*"]")    printf '%s' "$v"; return 0 ;;
    esac
    # Backslash first. Any other order escapes the backslashes this step adds.
    str_replace "$v" '\' '\\' esc
    str_replace "$esc" '"' '\"' esc
    str_replace "$esc" "$_TW_NL" '\n' esc
    str_replace "$esc" "$_TW_CR" '\r' esc
    str_replace "$esc" "$_TW_TAB" '\t' esc
    str_replace "$esc" "$_TW_BS" '\b' esc
    str_replace "$esc" "$_TW_FF" '\f' esc
    printf '"%s"' "$esc"
}

#[pub]
# Remove a key, leaving everything else alone.
#
# The key is a path, as for `toml_set`. Every line its value spans goes, and
# nothing else. A key that is not there leaves the file as it was.
# Usage: toml_unset "file.toml" "section.key" -> returns 2 for a shape one line cannot change
toml_unset() {
    local file="${1:-}" key="${2:-}" verb=unset span
    [[ -f "$file" && -n "$key" ]] || return 1
    _tw_place "$file" "$key" unset || return $?
    [[ -n "$_tw_node" ]] || return 0
    mapfile -t _tw_lines < "$file"
    read -r -a span <<< "${_TOML_W[$_tw_node]}"
    _tw_edit "${span[0]}" "${span[1]}"
    _tw_out "$file"
}
