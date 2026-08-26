#!/usr/bin/env bash
# =============================================================================
# nutshell/toml/json.sh - TOML as JSON
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Converting to another format is a job of its own, and it is the only part of
# the toml module that has to know what JSON looks like.
# =============================================================================

nut_once || return 0

use super::toml


#[pub]
# Convert a TOML file to JSON.
#
# Sections nest the way TOML says they do: `[a.b]` after `[a]` is `b` inside
# `a`, not a second `a` beside it. That second `a` was what this produced, and
# a JSON object with the same key twice loses whichever half the reader's
# parser discards.
#
# Sections are read in file order and a closed one is not reopened. A file that
# leaves a section and comes back to it, or that writes `[b]` before `[a.c]`
# when `[a]` is already behind it, cannot be converted in one pass without
# building the whole tree first, so it is refused by name rather than converted
# into an object with a repeated key.
#
# That refusal covers the reopened section and nothing else. This is a one-pass
# reader, not a validator: a key repeated inside one section comes out as a
# repeated key, an integer with a leading zero comes out as written, and an
# array holding a comma inside a quoted element or another array is split on
# the wrong comma. A file that has been through `toml_get` without complaint is
# the input this is for.
# Usage: toml_to_json "file.toml" -> prints JSON, fails on a reopened section
toml_to_json() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && return 1

    local json="{"
    local need_comma=0
    local line clean_line
    local -a stack=()
    local -a seen=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        _toml_clean_into clean_line "$line"
        [[ -z "$clean_line" ]] && continue

        # Section header [section] or [section.subsection]
        if [[ "$clean_line" =~ ^\[([^\]]+)\]$ ]]; then
            local new_section="${BASH_REMATCH[1]}"
            local -a parts=()
            IFS='.' read -ra parts <<< "$new_section"

            # How much of the path we are already inside. Only what differs
            # gets closed, so a child section stays within its parent.
            local common=0
            while (( common < ${#stack[@]} && common < ${#parts[@]} )) \
                  && [[ "${stack[$common]}" == "${parts[$common]}" ]]; do
                common=$(( common + 1 ))
            done

            local i
            for (( i = ${#stack[@]}; i > common; i-- )); do
                json+="}"
                unset 'stack[-1]'
                need_comma=1
            done

            local path="" p
            for (( i = 0; i < common; i++ )); do
                path+="${path:+.}${stack[$i]}"
            done
            for (( i = common; i < ${#parts[@]}; i++ )); do
                p="${parts[$i]}"
                path+="${path:+.}${p}"
                for prev in ${seen[@]+"${seen[@]}"}; do
                    if [[ "$prev" == "$path" ]]; then
                        printf 'toml_to_json: %s: section [%s] comes back to a part of the file already written\n' \
                            "$file" "$new_section" >&2
                        return 1
                    fi
                done
                seen+=("$path")
                [[ $need_comma -eq 1 ]] && json+=","
                json+="$(_json_string "$p"):{"
                need_comma=0
                stack+=("$p")
            done
            continue
        fi

        # Key = value
        if [[ "$clean_line" =~ ^([^=]+)=(.*)$ ]]; then
            local key val
            key="$(str_trim "${BASH_REMATCH[1]}")"
            val="$(str_trim "${BASH_REMATCH[2]}")"

            [[ $need_comma -eq 1 ]] && json+=","
            need_comma=1

            # Through the string writer, because a key is a string: a quoted
            # key, or one with a quote in it, went in raw and the document was
            # not JSON at all.
            json+="$(_json_string "$key"):"
            json+="$(_toml_value_to_json "$val")"
        fi
    done < "$file"

    local i
    for (( i = ${#stack[@]}; i > 0; i-- )); do
        json+="}"
    done

    json+="}"
    echo "$json"
}

# Internal: a string as JSON writes it, quotes included.
#
# JSON has its own escapes and they are not TOML's. A tab is a real tab by the
# time it gets here and JSON will not take one raw inside a string.
_json_string() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '"%s"' "$s"
}

# Internal: Convert a TOML value to JSON
_toml_value_to_json() {
    local val="$1"
    
    # Boolean
    if [[ "$val" == "true" ]]; then
        echo "true"
        return
    fi
    if [[ "$val" == "false" ]]; then
        echo "false"
        return
    fi
    
    # Integer
    if [[ "$val" =~ ^-?[0-9]+$ ]]; then
        echo "$val"
        return
    fi
    
    # Float
    if [[ "$val" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
        echo "$val"
        return
    fi
    
    # Array
    if [[ "$val" =~ ^\[.*\]$ ]]; then
        local content="${val#[}"
        content="${content%]}"
        content="$(str_trim "$content")"
        
        local json_arr="["
        local first=1
        local in_quotes=0
        local item=""
        local i char
        
        for ((i=0; i<${#content}; i++)); do
            char="${content:$i:1}"
            
            if [[ "$char" == '"' ]]; then
                ((in_quotes = 1 - in_quotes))
                item+="$char"
            elif [[ "$char" == ',' && $in_quotes -eq 0 ]]; then
                item="$(str_trim "$item")"
                if [[ -n "$item" ]]; then
                    [[ $first -eq 0 ]] && json_arr+=","
                    first=0
                    json_arr+="$(_toml_value_to_json "$item")"
                fi
                item=""
            else
                item+="$char"
            fi
        done
        
        # Last item
        item="$(str_trim "$item")"
        if [[ -n "$item" ]]; then
            [[ $first -eq 0 ]] && json_arr+=","
            json_arr+="$(_toml_value_to_json "$item")"
        fi
        
        json_arr+="]"
        echo "$json_arr"
        return
    fi
    
    # Basic string. Its TOML escapes are decoded first: escaping the raw text
    # again wrote `\"` as `\\\"`, so a value with a quote or a backslash in it
    # came out of the conversion with the backslashes doubled.
    if [[ "$val" =~ ^\"(.*)\"$ ]]; then
        _json_string "$(_toml_unescape "${BASH_REMATCH[1]}")"
        printf '\n'
        return
    fi
    
    # Literal string, which has no escapes to decode.
    if [[ "$val" =~ ^\'(.*)\'$ ]]; then
        _json_string "${BASH_REMATCH[1]}"
        printf '\n'
        return
    fi
    
    # Unquoted - treat as string
    _json_string "$val"
    printf '\n'
}
