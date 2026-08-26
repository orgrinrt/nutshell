#!/usr/bin/env bash
# =============================================================================
# nutshell/core/toml.sh - TOML parsing
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
#[allow(loc = 400)]
# Layer 0 (Core): Depends on fs.sh, string.sh, validate.sh
#
# Pure TOML parsing functions. No caching, no config semantics.
# Handles basic TOML: key = "value", [sections], arrays, booleans.
# =============================================================================

# Prevent multiple inclusion
nut_once || return 0

# Declared, not sourced by path. A hand-rolled `source` loads the module and
# hides it from the module-contract check, which reads `use` lines, so the
# dependency was real and unrecorded at once. `_toml_clean_line` trims through
# `str_trim`, and until this line existed a caller that had not already loaded
# `string` got a toml module whose every read silently failed.
use string validate

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

# Remove inline comments and trim whitespace from a line
# Trim, without a subshell. `$(str_trim ...)` forks, and the reader calls it
# once or twice for every line of every file: fifty-five lines cost a hundred
# milliseconds, and something reading a manifest for seven keys paid it seven
# times. Parameter expansion does the same job in the current shell.
# The caller names the target, which makes two things the caller's business
# and neither of them safe to assume.
#
# A name matching one of our own locals is shadowed by it, and the write lands
# on the local instead: the caller's variable is untouched and nothing says so.
# Prefixing the locals narrowed that to eight names rather than removing it, so
# the reserved prefix is refused outright instead of hoped about.
#
# A name carrying an array subscript is EVALUATED by `printf -v`, so
# `arr[$(...)]` runs the command inside it. Only a plain identifier is
# accepted.
_toml_valid_target() {
    case "$1" in
        __toml_*) return 1 ;;
    esac
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

_toml_trim_into() {
    _toml_valid_target "$1" || return 2
    local __toml_v="$2"
    __toml_v="${__toml_v#"${__toml_v%%[![:space:]]*}"}"
    __toml_v="${__toml_v%"${__toml_v##*[![:space:]]}"}"
    printf -v "$1" '%s' "$__toml_v"
}

# The cleaner, likewise. Same rule about a `#` inside quotes; same result;
# no fork.
_toml_clean_into() {
    _toml_valid_target "$1" || return 2
    local __toml_out="$1" __toml_line="$2"
    local __toml_acc="" __toml_i __toml_c __toml_q=0 __toml_qc=""
    for (( __toml_i = 0; __toml_i < ${#__toml_line}; __toml_i++ )); do
        __toml_c="${__toml_line:__toml_i:1}"
        if [[ $__toml_q -eq 1 ]]; then
            # The same escaped-quote rule as `_toml_clean_line`. It was fixed
            # there and not here, and this is the copy on the hot path: every
            # read of a value, every section listing and the JSON conversion go
            # through it, so the truncation stayed for all of them.
            if [[ "$__toml_c" == "\\" && "$__toml_qc" == '"' \
                  && $(( __toml_i + 1 )) -lt ${#__toml_line} ]]; then
                __toml_acc+="$__toml_c"
                __toml_i=$(( __toml_i + 1 ))
                __toml_c="${__toml_line:__toml_i:1}"
            elif [[ "$__toml_c" == "$__toml_qc" ]]; then
                __toml_q=0
            fi
        elif [[ "$__toml_c" == '"' || "$__toml_c" == "'" ]]; then
            __toml_q=1; __toml_qc="$__toml_c"
        elif [[ "$__toml_c" == "#" ]]; then
            break
        fi
        __toml_acc+="$__toml_c"
    done
    _toml_trim_into "$__toml_out" "$__toml_acc"
}

_toml_clean_line() {
    local line="$1"

    # A `#` inside a quoted string is part of the value, not the start of a
    # comment. Truncating at the first one regardless, which is what this did,
    # silently emptied any value containing one: `public_api = "#[pub]"` parsed
    # as `public_api =` and every consumer got an empty string with no error to
    # explain it.
    local out="" i char in_quotes=0 quote=""
    for (( i = 0; i < ${#line}; i++ )); do
        char="${line:i:1}"
        if [[ "$in_quotes" -eq 1 ]]; then
            # An escaped quote inside a basic string does not close it. Read as
            # a terminator, the rest of the value falls outside the string and
            # a `#` in it truncates the line. TOML gives a literal string no
            # escapes at all, so the backslash only counts inside `"`.
            if [[ "$char" == "\\" && "$quote" == '"' && $(( i + 1 )) -lt ${#line} ]]; then
                out+="$char"
                i=$(( i + 1 ))
                char="${line:i:1}"
            elif [[ "$char" == "$quote" ]]; then
                in_quotes=0
            fi
        elif [[ "$char" == '"' || "$char" == "'" ]]; then
            in_quotes=1
            quote="$char"
        elif [[ "$char" == "#" ]]; then
            break
        fi
        out+="$char"
    done

    str_trim "$out"
}

# Decode the escapes a TOML basic string is allowed to carry.
#
# Only a basic string has them: a literal string is taken as typed, which is
# the whole difference between the two forms. Without this a value written
# with an escaped quote or a backslash reads back with the backslashes still
# in it, so a path or a piece of prose does not survive a write and a read.
_toml_unescape() {
    local s="$1"
    # Nothing to do, and this is on the path of every value in every file.
    if [[ "$s" != *\\* ]]; then
        printf '%s' "$s"
        return 0
    fi

    local out="" i char next
    for (( i = 0; i < ${#s}; i++ )); do
        char="${s:i:1}"
        if [[ "$char" != "\\" || $(( i + 1 )) -ge ${#s} ]]; then
            out+="$char"
            continue
        fi
        next="${s:i+1:1}"
        i=$(( i + 1 ))
        case "$next" in
            n)  out+=$'\n' ;;
            t)  out+=$'\t' ;;
            r)  out+=$'\r' ;;
            b)  out+=$'\b' ;;
            f)  out+=$'\f' ;;
            '"') out+='"' ;;
            "\\") out+="\\" ;;
            u|U)
                # \uXXXX and \UXXXXXXXX. printf knows the escape; anything
                # that is not the right number of hex digits is not one, and
                # is kept as typed rather than silently eaten.
                local n=4; [[ "$next" == "U" ]] && n=8
                local hex="${s:i+1:n}"
                if [[ "${#hex}" -eq "$n" && "$hex" =~ ^[0-9A-Fa-f]+$ ]]; then
                    # shellcheck disable=SC2059
                    out+="$(printf "\\$next$hex")"
                    i=$(( i + n ))
                else
                    out+="\\$next"
                fi
                ;;
            *)  out+="\\$next" ;;
        esac
    done
    printf '%s' "$out"
}

# Extract value, handling quotes
_toml_extract_value() {
    local raw="$1"
    raw="$(str_trim "$raw")"
    
    # Double-quoted string
    if [[ "$raw" =~ ^\"(.*)\"$ ]]; then
        _toml_unescape "${BASH_REMATCH[1]}"
        printf '\n'
        return 0
    fi
    
    # Single-quoted string (literal)
    if [[ "$raw" =~ ^\'(.*)\'$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # Unquoted value (number, boolean, etc.)
    echo "$raw"
}

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

#[pub]
# Get a value from a TOML file
# Usage: toml_get "file.toml" "key" -> prints value
# Usage: toml_get "file.toml" "section.key" -> prints value from [section]
# Usage: toml_get "file.toml" "section.subsection.key" -> prints value from [section.subsection]
toml_get() {
    local file="${1:-}"
    local key="${2:-}"
    
    [[ ! -f "$file" ]] && return 1
    [[ -z "$key" ]] && return 1
    
    local section=""
    local search_key="$key"
    
    # Check if key has section prefix (section.key or section.subsection.key)
    # We need to find the longest matching section name
    if [[ "$key" == *.* ]]; then
        # Try progressively shorter section prefixes until we find a match
        local test_section="$key"
        while [[ "$test_section" == *.* ]]; do
            test_section="${test_section%.*}"
            # Check if this section exists in the file
            if grep -qE "^\[${test_section}\]" "$file" 2>/dev/null; then
                section="$test_section"
                search_key="${key#${section}.}"
                break
            fi
        done
        
        # If no section found, use the simple split (first.rest)
        if [[ -z "$section" && "$key" == *.* ]]; then
            section="${key%%.*}"
            search_key="${key#*.}"
        fi
    fi
    
    local in_section=0
    local current_section=""
    local line clean_line
    local in_multiline_array=0
    local multiline_value=""
    local in_multiline_string=0
    local multiline_string=""
    local capture_string=0
    local multiline_delim=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # A multi-line basic string, collected from RAW lines. Everything
        # between the delimiters is literal, including a `#`, so the comment
        # stripper must not run over it. Without this the reader returned a
        # bare `"` for every such value, which callers then used as content.
        if [[ $in_multiline_string -eq 1 ]]; then
            if [[ "$line" == *"$multiline_delim"* ]]; then
                in_multiline_string=0
                if [[ $capture_string -eq 1 ]]; then
                    multiline_string+="${line%%"$multiline_delim"*}"
                    printf '%s' "$multiline_string"
                    return 0
                fi
                continue
            fi
            [[ $capture_string -eq 1 ]] && multiline_string+="${line}"$'\n'
            continue
        fi

        # If we're collecting a multiline array, keep collecting
        # Don't use _toml_clean_line here because it would strip # inside quoted strings
        if [[ $in_multiline_array -eq 1 ]]; then
            # Comments inside a multi-line array are still comments. This used
            # to keep the whole line, on the grounds that a `#` may sit inside
            # a quoted value -- which is true, and is exactly what
            # _toml_clean_line was written to handle. Keeping it meant the
            # comment text was appended into the array and then split on
            # commas, so a comment containing one swallowed the entry after it,
            # silently. A declared path simply stopped being read.
            local trimmed
            _toml_clean_into trimmed "$line"
            [[ -z "$trimmed" ]] && continue  # blank, or comment-only
            multiline_value+="$trimmed"
            # Check if this line closes the array (] not inside quotes)
            # Simple heuristic: line ends with ] or ],
            if [[ "$trimmed" == *"]" ]] || [[ "$trimmed" == "]," ]]; then
                in_multiline_array=0
                _toml_extract_value "$multiline_value"
                return 0
            fi
            continue
        fi
        
        _toml_clean_into clean_line "$line"
        [[ -z "$clean_line" ]] && continue
        
        # Section header
        if [[ "$clean_line" =~ ^\[([^\]]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            if [[ -z "$section" ]]; then
                in_section=0
            elif [[ "$current_section" == "$section" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi
        
        # A multi-line string opens here. Detected BEFORE the section gates,
        # because the body has to be skipped whatever section it sits in: a
        # body line reading `[n]` was being taken as a real section header, and
        # one reading `keymap = wrong` was returned as a real setting, from a
        # section the caller never asked about.
        if [[ "$clean_line" =~ ^([^=]+)=(.*)$ ]]; then
            # Copied out before anything else runs. BASH_REMATCH is global and
            # any `[[ =~ ]]` anywhere -- including inside a function called
            # between the two reads -- replaces it. Reading group two after a
            # call that matched something else gets nothing, under `set -u`
            # loudly and otherwise silently.
            local __raw_k="${BASH_REMATCH[1]}" __raw_v="${BASH_REMATCH[2]}"
            local __k __v
            _toml_trim_into __k "$__raw_k"
            _toml_trim_into __v "$__raw_v"
            # Basic and literal delimiters both. They differ in escape
            # handling, which this reader does no processing of either way, so
            # the only difference that matters here is which three characters
            # close it.
            local __d=""
            [[ "$__v" == '"""'* ]] && __d='"""'
            [[ "$__v" == "'''"* ]] && __d="'''"
            if [[ -n "$__d" && "${__v#"$__d"}" != *"$__d"* ]]; then
                in_multiline_string=1
                multiline_delim="$__d"
                capture_string=0
                # Captured only when it is the value being looked for, and only
                # when we are in the right section for it.
                if [[ "$__k" == "$search_key" ]] \
                   && { [[ -z "$section" && -z "$current_section" ]] \
                        || [[ -n "$section" && $in_section -eq 1 ]]; }; then
                    capture_string=1
                    local __opening="${__v#"$__d"}"
                    multiline_string="${__opening:+${__opening}$'\n'}"
                fi
                continue
            fi
        fi

        # Skip if we need a section but aren't in it
        if [[ -n "$section" && $in_section -eq 0 ]]; then
            continue
        fi
        
        # Skip if we don't want a section but are in one
        if [[ -z "$section" && -n "$current_section" ]]; then
            continue
        fi
        
        # Key = value
        if [[ "$clean_line" =~ ^([^=]+)=(.*)$ ]]; then
            local raw_k="${BASH_REMATCH[1]}" raw_v="${BASH_REMATCH[2]}"
            local k v
            _toml_trim_into k "$raw_k"
            _toml_trim_into v "$raw_v"
            
            if [[ "$k" == "$search_key" ]]; then
                # A triple-quoted value. Closed on the same line when there
                # is a second delimiter after the first; otherwise it runs on.
                # The single-line form of either delimiter.
                local __sd=""
                [[ "$v" == '"""'* ]] && __sd='"""'
                [[ "$v" == "'''"* ]] && __sd="'''"
                if [[ -n "$__sd" ]]; then
                    local rest="${v#"$__sd"}"
                    printf '%s' "${rest%%"$__sd"*}"
                    return 0
                fi

                # Check if value starts an array that spans multiple lines
                if [[ "$v" == "["* && "$v" != *"]"* ]]; then
                    in_multiline_array=1
                    multiline_value="$v"
                    continue
                fi
                _toml_extract_value "$v"
                return 0
            fi
        fi
    done < "$file"
    
    return 1
}

#[pub]
# Get a value with a default if not found
# Usage: toml_get_or "file.toml" "key" "default" -> prints the value, or the default when the key is absent
toml_get_or() {
    local file="${1:-}"
    local key="${2:-}"
    local default="${3:-}"
    
    local value
    if value="$(toml_get "$file" "$key")"; then
        echo "$value"
    else
        echo "$default"
    fi
}

#[pub]
# Check if a key exists in a TOML file
# Usage: toml_has "file.toml" "key" -> returns 0 (true) or 1 (false)
toml_has() {
    local file="${1:-}"
    local key="${2:-}"
    
    toml_get "$file" "$key" >/dev/null 2>&1
}

#[pub]
# List all section names in a TOML file
# Usage: toml_sections "file.toml" -> prints section names, one per line
toml_sections() {
    local file="${1:-}"
    [[ ! -f "$file" ]] && return 1
    
    local line clean_line
    while IFS= read -r line || [[ -n "$line" ]]; do
        clean_line="$(_toml_clean_line "$line")"
        if [[ "$clean_line" =~ ^\[([^\]]+)\]$ ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done < "$file"
}

#[pub]
# List all keys in a section (or root if no section specified)
# Usage: toml_keys "file.toml" [section] -> prints one key per line, root keys when no section is named
toml_keys() {
    local file="${1:-}"
    local section="${2:-}"
    
    [[ ! -f "$file" ]] && return 1
    
    local in_section=0
    local current_section=""
    local line clean_line
    
    # If no section specified, we want root-level keys
    [[ -z "$section" ]] && in_section=1
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        _toml_clean_into clean_line "$line"
        [[ -z "$clean_line" ]] && continue
        
        # Section header
        if [[ "$clean_line" =~ ^\[([^\]]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            if [[ -z "$section" ]]; then
                in_section=0  # Stop reading root keys when we hit a section
            elif [[ "$current_section" == "$section" ]]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi
        
        [[ $in_section -eq 0 ]] && continue
        
        # Skip lines that start with quotes (array elements, not keys)
        [[ "$clean_line" =~ ^[\"\'] ]] && continue
        
        # Key = value (key must not start with quote)
        if [[ "$clean_line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*= ]]; then
            echo "${BASH_REMATCH[1]}"
        fi
    done < "$file"
}

#[pub]
# Check if a section exists in a TOML file, literally or implicitly
# `toml_has` answers for keys and only keys: it delegates to `toml_get`, and a
# section header has no value to return, so asking it about `[server]` says no
# while `toml_sections` lists it. That gap is easy to walk into and hard to see
# once you have, because the failure looks like a missing file.
#
# "Exists" means the TABLE exists, not that a header was literally written.
# `[a.b.c]` creates `a` and `a.b` per TOML v1.0.0, so both answer true here.
# That has to match `toml_subsections`, which reports children of exactly those
# implicit parents; a stricter reading would have made the obvious composition
# `toml_has_section f "$p" && toml_subsections f "$p"` silently skip them.
#
# Quoted keys containing dots (`[x."a.b"]`) are not understood, in common with
# the rest of this module.
# Usage: toml_has_section "file.toml" "server" -> returns 0 (true) or 1 (false)
toml_has_section() {
    local file="${1:-}"
    local section="${2:-}"

    [[ -f "$file" && -n "$section" ]] || return 1

    # Cheap reject before the per-line scan. A predicate gets called in loops,
    # and _toml_clean_line forks a subshell per line, so a full pass to answer
    # "no" costs seconds on a large file. grep against the FILE is safe here;
    # piping a shell function into `grep -q` is not, because grep exits on the
    # first match, the writer takes SIGPIPE, and a caller running with
    # `set -o pipefail` sees 141 for a successful lookup.
    grep -q '^[[:space:]]*\[' -- "$file" || return 1

    local line clean_line found
    while IFS= read -r line || [[ -n "$line" ]]; do
        clean_line="$(_toml_clean_line "$line")"
        if [[ "$clean_line" =~ ^\[([^\]]+)\]$ ]]; then
            found="${BASH_REMATCH[1]}"
            # Literal, or an ancestor of a deeper header.
            [[ "$found" == "$section" || "$found" == "$section."* ]] && return 0
        fi
    done < "$file"
    return 1
}

#[pub]
# List the direct children of a section, by name, without duplicates
# `[a.b.c]` makes `a.b` a table whether or not `[a.b]` was ever written, so a
# child is counted from any descendant header rather than only from a literal
# one. Under parent `a`, both `[a.b]` and `[a.b.c]` yield `b`, once.
# Reading a tree of named sub-tables otherwise means piping `toml_sections`
# into sed with a pattern built by hand, which every caller writes slightly
# differently and one of them writes wrong.
#
# Quoted keys containing dots (`[x."a.b"]`) are not understood: the name would
# be split inside the quotes and yield a fragment rather than a table. Such
# headers are skipped rather than mangled.
# Usage: toml_subsections "file.toml" "kind.gpg" -> child names, one per line
toml_subsections() {
    local file="${1:-}"
    local parent="${2:-}"

    [[ -f "$file" && -n "$parent" ]] || return 1

    local section rest child
    local -a seen=()
    while IFS= read -r section; do
        [[ "$section" == "$parent."* ]] || continue
        # A quoted key may contain a dot; splitting on it would emit half a
        # name. Skip rather than lie about the answer.
        case "$section" in *\"*|*\'*) continue ;; esac
        rest="${section#"$parent".}"
        child="${rest%%.*}"
        [[ -n "$child" ]] || continue
        # Emit each child once, however many descendants it has. This is
        # `arr_contains` open-coded, and O(n^2), on purpose: toml is layer 0
        # and its dependency line is `string validate`. Pulling in `array` to
        # save a loop over a handful of section names would buy a dependency
        # with a micro-optimisation.
        local s found=0
        for s in "${seen[@]:-}"; do [[ "$s" == "$child" ]] && { found=1; break; }; done
        (( found )) && continue
        seen+=("$child")
        printf '%s\n' "$child"
    done < <(toml_sections "$file")
}

#[pub]
# Parse a TOML array value into a bash array
# Usage: toml_array "file.toml" "key" arr
toml_array() {
    local file="${1:-}"
    local key="${2:-}"
    local -n _arr="${3:-_toml_array_result}"
    
    _arr=()
    
    local value
    value="$(toml_get "$file" "$key")" || return 1
    
    # Check if it's an array format: [ "a", "b", "c" ]
    if [[ "$value" =~ ^\[.*\]$ ]]; then
        # Remove brackets
        value="${value#[}"
        value="${value%]}"
        value="$(str_trim "$value")"
        
        # Split by comma, handling quoted strings
        local in_quotes=0
        local current=""
        local char
        local i
        
        for ((i=0; i<${#value}; i++)); do
            char="${value:$i:1}"
            
            if [[ "$char" == '"' ]]; then
                ((in_quotes = 1 - in_quotes))
            elif [[ "$char" == ',' && $in_quotes -eq 0 ]]; then
                current="$(str_trim "$current")"
                [[ -n "$current" ]] && _arr+=("$(_toml_extract_value "$current")")
                current=""
                continue
            fi
            
            current+="$char"
        done
        
        # Don't forget the last element
        current="$(str_trim "$current")"
        [[ -n "$current" ]] && _arr+=("$(_toml_extract_value "$current")")
    else
        # Single value, treat as single-element array
        _arr+=("$value")
    fi

    # Explicit, because the last statement above is a test. A trailing comma
    # leaves the final element empty, that test is false, and the function
    # would report failure having just populated the array correctly. TOML
    # permits the trailing comma, so this was every well-formed multi-line
    # array whose author used one.
    return 0
}

#[pub]
# Check if a TOML value is true (handles various boolean representations)
# Usage: toml_is_true "file.toml" "key" -> returns 0 (true) or 1 (false)
toml_is_true() {
    local file="${1:-}"
    local key="${2:-}"
    
    local value
    value="$(toml_get "$file" "$key")" || return 1
    
    is_truthy "$value"
}

#[pub]
# Get all key=value pairs from a section as "key=value" lines
# Usage: toml_section_pairs "file.toml" "section" -> prints one key=value per line, values already unquoted
toml_section_pairs() {
    local file="${1:-}"
    local section="${2:-}"
    
    [[ ! -f "$file" ]] && return 1
    [[ -z "$section" ]] && return 1
    
    local in_section=0
    local current_section=""
    local line clean_line
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        _toml_clean_into clean_line "$line"
        [[ -z "$clean_line" ]] && continue
        
        # Section header
        if [[ "$clean_line" =~ ^\[([^\]]+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            if [[ "$current_section" == "$section" ]]; then
                in_section=1
            else
                [[ $in_section -eq 1 ]] && break  # We've left our section
                in_section=0
            fi
            continue
        fi
        
        [[ $in_section -eq 0 ]] && continue
        
        # Key = value
        if [[ "$clean_line" =~ ^([^=]+)=(.*)$ ]]; then
            local k v
            k="$(str_trim "${BASH_REMATCH[1]}")"
            v="$(_toml_extract_value "$(str_trim "${BASH_REMATCH[2]}")")"
            echo "${k}=${v}"
        fi
    done < "$file"
}
