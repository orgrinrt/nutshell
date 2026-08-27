#!/bin/sh
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

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot depend on a bash-only function to
# decide whether it has been loaded: under a POSIX shell `nut_once` is not
# found, the `|| return 0` returns from the whole file, and the module then
# defines nothing while reporting success.
[ -n "${_NUTSHELL_TOML_WRITE_SH:-}" ] && return 0
_NUTSHELL_TOML_WRITE_SH=1

# The control characters a basic string escapes, as themselves. Built once,
# because there is no `$'\n'` here to write one inline with. The trailing `.`
# is because command substitution strips trailing newlines and the newline is
# the one that matters most.
_TW_NL="$(printf '\n.')"; _TW_NL="${_TW_NL%.}"
_TW_CR="$(printf '\r.')"; _TW_CR="${_TW_CR%.}"
_TW_TAB="$(printf '\t.')"; _TW_TAB="${_TW_TAB%.}"
_TW_BS="$(printf '\b.')"; _TW_BS="${_TW_BS%.}"
_TW_FF="$(printf '\f.')"; _TW_FF="${_TW_FF%.}"

# Leading, then trailing, whitespace off a string, into `_tw_s`.
#
# One character at a time because POSIX parameter expansion has no repetition
# and there is no `[[:space:]]*` to anchor against. Both `[[ ]]` regexes this
# replaced trimmed spaces and tabs only, which is what this trims.
_tw_trim() {
    _tw_s="$1"
    while :; do
        case "$_tw_s" in
            " "*|"${_TW_TAB}"*) _tw_s="${_tw_s#?}" ;;
            *) break ;;
        esac
    done
    while :; do
        case "$_tw_s" in
            *" "|*"${_TW_TAB}") _tw_s="${_tw_s%?}" ;;
            *) break ;;
        esac
    done
}

# The name inside a `[section]` header, into the named variable. Fails when the
# line is not one.
#
# The regex this replaced was `^[[:space:]]*\[(.+)\][[:space:]]*$`, and `.+` is
# greedy: `[a][b]` captured `a][b`. Taking everything between the first `[` and
# the last `]` keeps that, which matters because the reader does the same and
# the two have to agree about what a header is.
_tw_header_of() {
    _tw_trim "$1"
    case "$_tw_s" in
        "["*"]") ;;
        *) return 1 ;;
    esac
    _tw_s="${_tw_s#"["}"
    _tw_s="${_tw_s%"]"}"
    # `.+` needs at least one character, so `[]` is not a header.
    [ -n "$_tw_s" ] || return 1
    eval "$2=\$_tw_s"
    return 0
}

# Whether a line assigns the given leaf key: optional indent, the name,
# optional space, `=`.
_tw_is_key() {
    _tw_trim "$1"
    case "$_tw_s" in
        "$2"*) ;;
        *) return 1 ;;
    esac
    _tw_s="${_tw_s#"$2"}"
    while :; do
        case "$_tw_s" in
            " "*|"${_TW_TAB}"*) _tw_s="${_tw_s#?}" ;;
            *) break ;;
        esac
    done
    case "$_tw_s" in "="*) return 0 ;; esac
    return 1
}

# Whether a line carries anything that is not a space.
#
# `[[ -n "${line// }" ]]` stripped spaces only, so a line of tabs counted as
# carrying something. This keeps that rather than tidying it, because the
# position an appended key lands at depends on it.
_tw_has_content() {
    case "$1" in *[!" "]*) return 0 ;; esac
    return 1
}

# Every occurrence of one string swapped for another, into the named variable.
# There is no `${x//a/b}` here.
_tw_gsub() {
    # An empty needle matches everywhere and the loop never shortens the
    # remainder, so it appends forever. `str_replace` guards this on its first
    # line and this copy did not, which is the cost of the second copy.
    [ -n "$2" ] || { eval "$4=\$1"; return 0; }
    # The out-name reaches `eval`, so it is checked the way every other
    # out-name in this library is: `_json_gsub a b c 'v; echo X'` ran the echo.
    case "$4" in
        ''|*[!A-Za-z0-9_]*|[0-9]*) return 2 ;;
    esac
    _tw_rest="$1"; _tw_acc=""
    while :; do
        case "$_tw_rest" in
            *"$2"*)
                _tw_acc="${_tw_acc}${_tw_rest%%"$2"*}$3"
                _tw_rest="${_tw_rest#*"$2"}"
                ;;
            *) break ;;
        esac
    done
    eval "$4=\${_tw_acc}\${_tw_rest}"
}

# A run of digits, with an optional leading minus, and at least one digit.
_tw_is_int() {
    _tw_v="${1#-}"
    [ -n "$_tw_v" ] || return 1
    case "$_tw_v" in *[!0-9]*) return 1 ;; esac
    return 0
}

# The same with exactly one dot, and digits on both sides of it.
_tw_is_float() {
    _tw_v="${1#-}"
    case "$_tw_v" in *.*) ;; *) return 1 ;; esac
    _tw_i="${_tw_v%%.*}"; _tw_f="${_tw_v#*.}"
    [ -n "$_tw_i" ] && [ -n "$_tw_f" ] || return 1
    case "$_tw_f" in *.*) return 1 ;; esac
    case "${_tw_i}${_tw_f}" in *[!0-9]*) return 1 ;; esac
    return 0
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
# A key with no section is a key before the first `[header]`, and only there. A
# key in a section that does not exist yet gets the section appended. A key that
# is not there gets appended inside its own section, after the last line that
# belongs to it, rather than at the end of the file where it would land in
# somebody else's.
#
# Usage: toml_set "file.toml" "section.key" "value"
toml_set() {
    _tws_file="$1"; _tws_key="$2"; _tws_value="$3"
    [ -n "$_tws_file" ] && [ -n "$_tws_key" ] || return 1

    _tws_section=""; _tws_leaf="$_tws_key"
    case "$_tws_key" in
        *.*) _tws_section="${_tws_key%.*}"; _tws_leaf="${_tws_key##*.}" ;;
    esac

    _tws_written="$(_toml_write_value "$_tws_value")"

    [ -f "$_tws_file" ] || { printf '' > "$_tws_file" 2>/dev/null || return 1; }

    _tws_tmp="$(mktemp)" || return 1
    _tws_in_section=0; _tws_done_it=0; _tws_last_in_section=0; _tws_line=""; _tws_n=0; _tws_seen_section=0
    _tws_hdr=""

    # One pass to find where the key's own part of the file ends, so an appended
    # key lands inside it rather than at the end of the file. A section with
    # nothing in it ends at its own header, which is why the header line counts.
    #
    # Root is a part of the file like any other: it runs from the first line to
    # the line before the first header. `last_in_section` of 0 means it is empty,
    # which for root means the file opens with a header and the new key goes
    # above it.
    if [ -n "$_tws_section" ]; then
        while IFS= read -r _tws_line || [ -n "$_tws_line" ]; do
            _tws_n=$(( _tws_n + 1 ))
            if _tw_header_of "$_tws_line" _tws_hdr; then
                if [ "$_tws_hdr" = "$_tws_section" ]; then
                    _tws_in_section=1; _tws_seen_section=1; _tws_last_in_section="$_tws_n"
                else
                    _tws_in_section=0
                fi
                continue
            fi
            if [ "$_tws_in_section" -eq 1 ] && _tw_has_content "$_tws_line"; then
                _tws_last_in_section="$_tws_n"
            fi
        done < "$_tws_file"
    else
        _tws_seen_section=1
        while IFS= read -r _tws_line || [ -n "$_tws_line" ]; do
            _tws_n=$(( _tws_n + 1 ))
            _tw_header_of "$_tws_line" _tws_hdr && break
            _tw_has_content "$_tws_line" && _tws_last_in_section="$_tws_n"
        done < "$_tws_file"
    fi

    # Root is a place, not the absence of one: everything before the first
    # header. Reading it as "no section is open" made a root key match the first
    # section that happened to have a key by that name, so `toml_set f name x`
    # rewrote `[a] name` and `toml_get f name` then found nothing.
    _tws_at_root=1
    _tws_in_section=0; _tws_n=0

    # The file opens with a header and the key belongs above it.
    if [ "$_tws_done_it" -eq 0 ] && [ -z "$_tws_section" ] && [ "$_tws_last_in_section" -eq 0 ]; then
        printf '%s = %s\n' "$_tws_leaf" "$_tws_written" >> "$_tws_tmp"
        _tws_done_it=1
    fi

    while IFS= read -r _tws_line || [ -n "$_tws_line" ]; do
        _tws_n=$(( _tws_n + 1 ))
        if _tw_header_of "$_tws_line" _tws_hdr; then
            _tws_at_root=0
            _tws_in_section=0
            [ "$_tws_hdr" = "$_tws_section" ] && _tws_in_section=1
            printf '%s\n' "$_tws_line" >> "$_tws_tmp"
            # An empty section ends at its header, so the append has to be
            # possible here too.
            if [ "$_tws_done_it" -eq 0 ] && [ -n "$_tws_section" ] && [ "$_tws_n" -eq "$_tws_last_in_section" ]; then
                printf '%s = %s\n' "$_tws_leaf" "$_tws_written" >> "$_tws_tmp"
                _tws_done_it=1
            fi
            continue
        fi

        # The key itself, in the right place, replaced so its comment and its
        # neighbours survive.
        _tw_here=0
        if [ -z "$_tws_section" ] && [ "$_tws_at_root" -eq 1 ]; then
            _tw_here=1
        elif [ "$_tws_in_section" -eq 1 ]; then
            _tw_here=1
        fi
        if [ "$_tws_done_it" -eq 0 ] && [ "$_tw_here" -eq 1 ] && _tw_is_key "$_tws_line" "$_tws_leaf"; then
            printf '%s = %s\n' "$_tws_leaf" "$_tws_written" >> "$_tws_tmp"
            _tws_done_it=1
            continue
        fi

        printf '%s\n' "$_tws_line" >> "$_tws_tmp"

        # Not there, but its part of the file is: append where that part ends.
        if [ "$_tws_done_it" -eq 0 ] && [ "$_tws_n" -eq "$_tws_last_in_section" ]; then
            printf '%s = %s\n' "$_tws_leaf" "$_tws_written" >> "$_tws_tmp"
            _tws_done_it=1
        fi
    done < "$_tws_file"

    if [ "$_tws_done_it" -eq 0 ]; then
        if [ -n "$_tws_section" ] && [ "$_tws_seen_section" -eq 0 ]; then
            [ -s "$_tws_tmp" ] && printf '\n' >> "$_tws_tmp"
            printf '[%s]\n' "$_tws_section" >> "$_tws_tmp"
        fi
        printf '%s = %s\n' "$_tws_leaf" "$_tws_written" >> "$_tws_tmp"
    fi

    # Renamed into place, so a reader never sees a half-written file and a
    # crash partway leaves the original intact.
    mv -f "$_tws_tmp" "$_tws_file" || { rm -f "$_tws_tmp"; return 1; }
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
    _twv="$1"
    if _tw_is_int "$_twv" || _tw_is_float "$_twv"; then
        printf '%s' "$_twv"; return 0
    fi
    case "$_twv" in
        true|false) printf '%s' "$_twv"; return 0 ;;
        "["*"]")    printf '%s' "$_twv"; return 0 ;;
    esac
    # Backslash first. Any other order escapes the backslashes this step adds.
    _tw_gsub "$_twv" '\' '\\' _twv_esc
    _tw_gsub "$_twv_esc" '"' '\"' _twv_esc
    _tw_gsub "$_twv_esc" "$_TW_NL" '\n' _twv_esc
    _tw_gsub "$_twv_esc" "$_TW_CR" '\r' _twv_esc
    _tw_gsub "$_twv_esc" "$_TW_TAB" '\t' _twv_esc
    _tw_gsub "$_twv_esc" "$_TW_BS" '\b' _twv_esc
    _tw_gsub "$_twv_esc" "$_TW_FF" '\f' _twv_esc
    printf '"%s"' "$_twv_esc"
}

#[pub]
# Remove a key, leaving everything else alone.
#
# A key with no section means one before the first `[header]`. Reading that as
# "no section is open" deleted the key from every section in the file.
# Usage: toml_unset "file.toml" "section.key"
toml_unset() {
    _twu_file="$1"; _twu_key="$2"
    [ -f "$_twu_file" ] && [ -n "$_twu_key" ] || return 1

    _twu_section=""; _twu_leaf="$_twu_key"
    case "$_twu_key" in
        *.*) _twu_section="${_twu_key%.*}"; _twu_leaf="${_twu_key##*.}" ;;
    esac

    _twu_tmp="$(mktemp)" || return 1
    _twu_in_section=0; _twu_at_root=1; _twu_line=""; _twu_hdr=""
    while IFS= read -r _twu_line || [ -n "$_twu_line" ]; do
        if _tw_header_of "$_twu_line" _twu_hdr; then
            _twu_at_root=0
            _twu_in_section=0
            [ "$_twu_hdr" = "$_twu_section" ] && _twu_in_section=1
            printf '%s\n' "$_twu_line" >> "$_twu_tmp"; continue
        fi
        _tw_here=0
        if [ -z "$_twu_section" ] && [ "$_twu_at_root" -eq 1 ]; then
            _tw_here=1
        elif [ "$_twu_in_section" -eq 1 ]; then
            _tw_here=1
        fi
        if [ "$_tw_here" -eq 1 ] && _tw_is_key "$_twu_line" "$_twu_leaf"; then
            continue
        fi
        printf '%s\n' "$_twu_line" >> "$_twu_tmp"
    done < "$_twu_file"

    mv -f "$_twu_tmp" "$_twu_file" || { rm -f "$_twu_tmp"; return 1; }
    return 0
}
