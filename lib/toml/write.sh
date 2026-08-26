#!/usr/bin/env bash
# =============================================================================
# nutshell/toml/write.sh - Changing a TOML file without rewriting it
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Reading TOML and editing TOML are different jobs and they live apart. The
# reader parses; this one leaves the file alone except for the line it came
# for.
# =============================================================================

nut_once || return 0

#[pub]
# Write a value, leaving the rest of the file as it was.
#
# Editing a config file is not the same as generating one. A person wrote the
# comments in it, chose the order, put a blank line where they wanted a pause,
# and a setter that rewrites the file from a parsed model throws all of that
# away the first time anything saves. So: find the line, change the line, and
# touch nothing else.
#
# A key in a section that does not exist yet gets the section appended. A key
# that is not there gets appended inside its section, after the last line that
# belongs to it, rather than at the end of the file where it would land in
# somebody else's section.
#
# Usage: toml_set "file.toml" "section.key" "value"
toml_set() {
    local file="$1" key="$2" value="$3"
    [[ -n "$file" && -n "$key" ]] || return 1

    local section="" leaf="$key"
    if [[ "$key" == *.* ]]; then
        section="${key%.*}"; leaf="${key##*.}"
    fi

    # Written as TOML: a value that looks like a number or a bool goes in bare,
    # anything else is quoted, and a quoted value has its quotes and
    # backslashes escaped. Without that, a path with a backslash or a string
    # with a quote in it writes a file that no longer parses.
    local written
    if [[ "$value" =~ ^-?[0-9]+$ ]] || [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]] \
       || [[ "$value" == "true" || "$value" == "false" ]] \
       || [[ "$value" == \[*\] ]]; then
        written="$value"
    else
        local esc="${value//\\/\\\\}"
        esc="${esc//\"/\\\"}"
        written="\"${esc}\""
    fi

    [[ -f "$file" ]] || { printf '' > "$file" 2>/dev/null || return 1; }

    local tmp; tmp="$(mktemp)" || return 1
    local in_section=0 done_it=0 last_in_section=0 line n=0 seen_section=0

    # One pass to find where the section ends, so an appended key lands inside
    # it rather than at the end of the file.
    if [[ -n "$section" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            n=$(( n + 1 ))
            if [[ "$line" =~ ^[[:space:]]*\[(.+)\][[:space:]]*$ ]]; then
                if [[ "${BASH_REMATCH[1]}" == "$section" ]]; then
                    in_section=1; seen_section=1; last_in_section="$n"
                else
                    in_section=0
                fi
                continue
            fi
            (( in_section == 1 )) && [[ -n "${line// }" ]] && last_in_section="$n"
        done < "$file"
    fi

    in_section=0; n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$(( n + 1 ))
        if [[ "$line" =~ ^[[:space:]]*\[(.+)\][[:space:]]*$ ]]; then
            in_section=0
            [[ "${BASH_REMATCH[1]}" == "$section" ]] && in_section=1
            printf '%s\n' "$line" >> "$tmp"
            continue
        fi

        # The key itself, in the right section, replaced in place so its
        # comment and its neighbours survive.
        if (( done_it == 0 )) \
           && { [[ -z "$section" && "$in_section" == 0 ]] || (( in_section == 1 )); } \
           && [[ "$line" =~ ^[[:space:]]*"$leaf"[[:space:]]*= ]]; then
            printf '%s = %s\n' "$leaf" "$written" >> "$tmp"
            done_it=1
            continue
        fi

        printf '%s\n' "$line" >> "$tmp"

        # Not there, but its section is: append where the section ends.
        if (( done_it == 0 )) && [[ -n "$section" ]] && (( n == last_in_section )); then
            printf '%s = %s\n' "$leaf" "$written" >> "$tmp"
            done_it=1
        fi
    done < "$file"

    if (( done_it == 0 )); then
        if [[ -n "$section" ]] && (( seen_section == 0 )); then
            [[ -s "$tmp" ]] && printf '\n' >> "$tmp"
            printf '[%s]\n' "$section" >> "$tmp"
        fi
        printf '%s = %s\n' "$leaf" "$written" >> "$tmp"
    fi

    # Renamed into place, so a reader never sees a half-written file and a
    # crash partway leaves the original intact.
    mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
    return 0
}

#[pub]
# Remove a key, leaving everything else alone.
# Usage: toml_unset "file.toml" "section.key"
toml_unset() {
    local file="$1" key="$2"
    [[ -f "$file" && -n "$key" ]] || return 1

    local section="" leaf="$key"
    if [[ "$key" == *.* ]]; then section="${key%.*}"; leaf="${key##*.}"; fi

    local tmp; tmp="$(mktemp)" || return 1
    local in_section=0 line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*\[(.+)\][[:space:]]*$ ]]; then
            in_section=0
            [[ "${BASH_REMATCH[1]}" == "$section" ]] && in_section=1
            printf '%s\n' "$line" >> "$tmp"; continue
        fi
        if { [[ -z "$section" && "$in_section" == 0 ]] || (( in_section == 1 )); } \
           && [[ "$line" =~ ^[[:space:]]*"$leaf"[[:space:]]*= ]]; then
            continue
        fi
        printf '%s\n' "$line" >> "$tmp"
    done < "$file"

    mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
    return 0
}
