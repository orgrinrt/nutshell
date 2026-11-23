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
#   a key inside an array of tables that the path does not index, `row.status`
#     where `row.3.status` names one row; a table to open by a header under any
#     row, which a header cannot name by its index;
#   a key inside an inline table, which is one value on one line;
#   a key a dotted key made, or one in a table a dotted key made, which is not
#     on a line of its own and whose table a header would define twice;
#   a key whose path runs into a value or an array.
_tw_place() {
    local file="$1" key="$2" verb="$3" node=R seg t i last shown="" whole="" via=0
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
            aot)   _tw_row "$seg" "$i" "$last"
                   case $? in
                       0) node="$_tw_row_node"; i=$(( i + 1 )); via=1 ;;
                       1) _tw_node=""; [[ "$verb" == unset ]]; return $? ;;
                       *) return 2 ;;
                   esac ;;
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
        (( via )) && { _tw_deny "a header cannot open a table under one row and not the last"; return 2; }
        _tw_head="$whole"
        return 0
    fi
    if [[ "$node" != R && "${_TOML_F[$node]}" != *[hi]* ]]; then
        _tw_deny "a dotted key, $shown, defines it or a table above it"; return 2
    fi
    if [[ "$node" != R && -z "${_TOML_E[$node]+x}" ]]; then
        (( via )) && { _tw_deny "a header cannot open a table under one row and not the last"; return 2; }
        _tw_head="$whole"
    fi
    seg="$node$_TOML_US${_tp_pseg[last]}"
    [[ -n "${_TOML_T[$seg]-}" ]] || return 0
    case "${_TOML_W[$seg]-}" in
        '')    _tw_deny "it is a table, not a value"; return 2 ;;
        *' '1) _tw_node="$seg" ;;
        *)     _tw_deny "a dotted key defines it, not a line of its own"; return 2 ;;
    esac
}

# _tw_row <array node> <i> <last> -> `_tw_row_node`, the row the segment after
# the array's name indexes, and the index added to `shown`
# rc 1 where the array has no such row, 2 where the segment is not an index or
# is the last one, so that it would be the row as a value.
_tw_row() {
    local idx="${_tp_pseg[$2 + 1]-}"
    if (( $2 + 1 >= $3 )) || ! [[ "$idx" =~ ^[0-9]{1,9}$ ]]; then
        _tw_deny "it is inside the array of tables [[$shown]]"; return 2
    fi
    idx=$(( 10#$idx ))
    if (( idx >= ${_TOML_N[$1]} )); then
        [[ "$verb" == unset ]] || _tw_deny "[[$shown]] has no row $idx"
        return 1
    fi
    _tw_row_node="$1$_TOML_US$idx"
    shown+=".$idx"
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
# A row of an array of tables is reached by its index, `row.3.status`. A row
# that is not there is rc 1.
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

#[pub]
# Append a new table to an array of tables, and print its path.
#
# The `[[path]]` header goes after the last line of the array's last row,
# including the tables under that row, so the rows stay together; an array the
# file has not got yet is opened at the end of the file. The new row is empty,
# `toml_set` fills it by the path this prints, `row.3`. Nothing else in the
# file moves.
#
# A path through an array of tables names its last row, since a header can say
# nothing else; an index in it is refused, with a path that is a table, a
# value, or inside an inline table.
# Usage: toml_append_table "file.toml" "row" -> prints row.3, returns 2 for a path one header cannot add to
toml_append_table() {
    local file="${1:-}" key="${2:-}" verb="append a table to" node=R seg t i last e k n=0 addr="" whole=""
    [[ -n "$file" && -n "$key" ]] || return 1
    [[ -f "$file" ]] || { : > "$file" 2>/dev/null || return 1; }
    _toml_open "$file" || return $?
    _toml_path_split "$key" || return 1
    last=$(( ${#_tp_pseg[@]} - 1 ))
    for (( i = 0; i <= last; i++ )); do
        _toml_seg_show "${_tp_pseg[i]}"; whole+="${whole:+.}${_ts_out}"
    done
    for (( i = 0; i <= last; i++ )); do
        seg="$node$_TOML_US${_tp_pseg[i]}"
        t="${_TOML_T[$seg]-}"
        [[ -n "$t" ]] || { addr=""; break; }
        _toml_seg_show "${_tp_pseg[i]}"; addr+="${addr:+.}${_ts_out}"
        case "$t" in
            aot)
                if (( i == last )); then
                    n="${_TOML_N[$seg]}"
                    node="$seg$_TOML_US$(( n - 1 ))"
                elif [[ "${_tp_pseg[i+1]}" =~ ^[0-9]{1,9}$ ]]; then
                    _tw_deny "a header names the last row, not row ${_tp_pseg[i+1]}"; return 2
                else
                    addr+=".$(( ${_TOML_N[$seg]} - 1 ))"
                    node="$seg$_TOML_US$(( ${_TOML_N[$seg]} - 1 ))"
                fi ;;
            table)
                if (( i == last )); then _tw_deny "it is a table, not an array of tables"; return 2; fi
                if [[ "${_TOML_F[$seg]}" == *X* ]]; then _tw_deny "it is inside the inline table $addr"; return 2; fi
                node="$seg" ;;
            *)
                _tw_deny "$addr is a value, not an array of tables"; return 2 ;;
        esac
    done
    mapfile -t _tw_lines < "$file"
    e=${#_tw_lines[@]}
    if (( n )); then
        e=-1
        for k in "${!_TOML_E[@]}"; do
            [[ "$k" == "$node" || "$k" == "$node$_TOML_US"* ]] && (( _TOML_E[$k] > e )) && e="${_TOML_E[$k]}"
        done
        for (( k = e + 1; k < ${#_tw_lines[@]}; k++ )); do
            [[ "${_tw_lines[k]%$'\r'}" =~ $_TOML_RE_BLANK ]] || break
        done
        (( k < ${#_tw_lines[@]} )) || e=${#_tw_lines[@]}
    fi
    if (( e < ${#_tw_lines[@]} )); then
        _tw_edit $(( e + 1 )) "$e" "[[${whole}]]"
        _tw_edit $(( e + 1 )) "$e" ""
    else
        e=${#_tw_lines[@]}
        _tw_edit "$e" $(( e - 1 )) "[[${whole}]]"
        (( e == 0 )) || [[ "${_tw_lines[e-1]%$'\r'}" =~ ^[[:blank:]]*$ ]] || _tw_edit "$e" $(( e - 1 )) ""
    fi
    _tw_out "$file" || return 1
    printf '%s.%s\n' "${addr:-$whole}" "$n"
}
