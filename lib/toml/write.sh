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
# A key with no section is a key before the first `[header]`, and only there. A
# key in a section that does not exist yet gets the section appended. A key that
# is not there gets appended inside its own section, after the last line that
# belongs to it, rather than at the end of the file where it would land in
# somebody else's.
#
# Usage: toml_set "file.toml" "section.key" "value"
toml_set() {
    local file="$1" key="$2" value="$3"
    [[ -n "$file" && -n "$key" ]] || return 1

    local section="" leaf="$key"
    if [[ "$key" == *.* ]]; then
        section="${key%.*}"; leaf="${key##*.}"
    fi

    local written; written="$(_toml_write_value "$value")"

    [[ -f "$file" ]] || { printf '' > "$file" 2>/dev/null || return 1; }

    local tmp; tmp="$(mktemp)" || return 1
    local in_section=0 done_it=0 last_in_section=0 line n=0 seen_section=0

    # One pass to find where the key's own part of the file ends, so an appended
    # key lands inside it rather than at the end of the file. A section with
    # nothing in it ends at its own header, which is why the header line counts.
    #
    # Root is a part of the file like any other: it runs from the first line to
    # the line before the first header. `last_in_section` of 0 means it is empty,
    # which for root means the file opens with a header and the new key goes
    # above it.
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
    else
        seen_section=1
        while IFS= read -r line || [[ -n "$line" ]]; do
            n=$(( n + 1 ))
            [[ "$line" =~ ^[[:space:]]*\[(.+)\][[:space:]]*$ ]] && break
            [[ -n "${line// }" ]] && last_in_section="$n"
        done < "$file"
    fi

    # Root is a place, not the absence of one: everything before the first
    # header. Reading it as "no section is open" made a root key match the first
    # section that happened to have a key by that name, so `toml_set f name x`
    # rewrote `[a] name` and `toml_get f name` then found nothing.
    local at_root=1
    in_section=0; n=0

    # The file opens with a header and the key belongs above it.
    if (( done_it == 0 )) && [[ -z "$section" ]] && (( last_in_section == 0 )); then
        printf '%s = %s\n' "$leaf" "$written" >> "$tmp"
        done_it=1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$(( n + 1 ))
        if [[ "$line" =~ ^[[:space:]]*\[(.+)\][[:space:]]*$ ]]; then
            at_root=0
            in_section=0
            [[ "${BASH_REMATCH[1]}" == "$section" ]] && in_section=1
            printf '%s\n' "$line" >> "$tmp"
            # An empty section ends at its header, so the append has to be
            # possible here too.
            if (( done_it == 0 )) && [[ -n "$section" ]] && (( n == last_in_section )); then
                printf '%s = %s\n' "$leaf" "$written" >> "$tmp"
                done_it=1
            fi
            continue
        fi

        # The key itself, in the right place, replaced so its comment and its
        # neighbours survive.
        if (( done_it == 0 )) \
           && { [[ -z "$section" ]] && (( at_root == 1 )) || (( in_section == 1 )); } \
           && [[ "$line" =~ ^[[:space:]]*"$leaf"[[:space:]]*= ]]; then
            printf '%s = %s\n' "$leaf" "$written" >> "$tmp"
            done_it=1
            continue
        fi

        printf '%s\n' "$line" >> "$tmp"

        # Not there, but its part of the file is: append where that part ends.
        if (( done_it == 0 )) && (( n == last_in_section )); then
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

# A value as TOML writes it.
#
# A number, a bool and an array go in bare; everything else is a basic string,
# and a basic string carries escapes. The five the reader decodes are the five
# encoded here: without them a value with a newline in it wrote a file that no
# longer parses at all, which loses every other key in it rather than the one
# being written.
_toml_write_value() {
    local value="$1"
    if [[ "$value" =~ ^-?[0-9]+$ ]] || [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]] \
       || [[ "$value" == "true" || "$value" == "false" ]] \
       || [[ "$value" == \[*\] ]]; then
        printf '%s' "$value"
        return 0
    fi
    local esc="${value//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    esc="${esc//$'\n'/\\n}"
    esc="${esc//$'\r'/\\r}"
    esc="${esc//$'\t'/\\t}"
    esc="${esc//$'\b'/\\b}"
    esc="${esc//$'\f'/\\f}"
    printf '"%s"' "$esc"
}

#[pub]
# Remove a key, leaving everything else alone.
#
# A key with no section means one before the first `[header]`. Reading that as
# "no section is open" deleted the key from every section in the file.
# Usage: toml_unset "file.toml" "section.key"
toml_unset() {
    local file="$1" key="$2"
    [[ -f "$file" && -n "$key" ]] || return 1

    local section="" leaf="$key"
    if [[ "$key" == *.* ]]; then section="${key%.*}"; leaf="${key##*.}"; fi

    local tmp; tmp="$(mktemp)" || return 1
    local in_section=0 at_root=1 line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*\[(.+)\][[:space:]]*$ ]]; then
            at_root=0
            in_section=0
            [[ "${BASH_REMATCH[1]}" == "$section" ]] && in_section=1
            printf '%s\n' "$line" >> "$tmp"; continue
        fi
        if { [[ -z "$section" ]] && (( at_root == 1 )) || (( in_section == 1 )); } \
           && [[ "$line" =~ ^[[:space:]]*"$leaf"[[:space:]]*= ]]; then
            continue
        fi
        printf '%s\n' "$line" >> "$tmp"
    done < "$file"

    mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
    return 0
}
