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

# `str_replace` with an out-name, for the escaping below. This file carried its
# own copy of that loop, as did `json.sh` and `extern.sh`; one of the three then
# diverged and shipped an injection hole that the other two did not have.
use string

# The control characters a basic string escapes, as themselves. Built once,
# because there is no `$'\n'` here to write one inline with. The trailing `.`
# is because command substitution strips trailing newlines and the newline is
# the one that matters most.
_TW_NL="$(printf '\n.')"; _TW_NL="${_TW_NL%.}"
_TW_CR="$(printf '\r.')"; _TW_CR="${_TW_CR%.}"
_TW_TAB="$(printf '\t.')"; _TW_TAB="${_TW_TAB%.}"
_TW_BS="$(printf '\b.')"; _TW_BS="${_TW_BS%.}"
_TW_FF="$(printf '\f.')"; _TW_FF="${_TW_FF%.}"
# An opening brace, so that no function body carries a lone one.
_TW_LB="$(printf '\173')"

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

# The path a header or a key spells, read up to <stop> outside quotes.
#
# Sets `_tw_path` to its segments joined by dots, each bare where TOML lets it
# be and in double quotes where it does not, so `[ "a.b" . c ]` and the key
# `"a.b".c.k` name the same section. `_tw_first` is the first segment,
# `_tw_nseg` the count, `_tw_after` what follows <stop>. Fails when <stop>
# never comes or a segment is empty.
#
# One byte at a time, because POSIX parameter expansion has no repetition. A
# header or a key is short; a value is never scanned here.
_tw_path_scan() {
    _tw_rest="$1"; _tw_path=""; _tw_first=""; _tw_nseg=0; _tw_seg=""
    _tw_q=""; _tw_quoted=0; _tw_bad=0
    while [ -n "$_tw_rest" ]; do
        _tw_c="${_tw_rest%"${_tw_rest#?}"}"; _tw_rest="${_tw_rest#?}"
        if [ -n "$_tw_q" ]; then
            if [ "$_tw_c" = "$_tw_q" ]; then
                _tw_q=""
            elif [ "$_tw_q" = '"' ] && [ "$_tw_c" = '\' ]; then
                _tw_seg="$_tw_seg$_tw_c${_tw_rest%"${_tw_rest#?}"}"; _tw_rest="${_tw_rest#?}"
            else
                _tw_seg="$_tw_seg$_tw_c"
            fi
            continue
        fi
        case "$_tw_c" in
            '"'|"'") _tw_q="$_tw_c"; _tw_quoted=1 ;;
            " "|"$_TW_TAB") ;;
            .) _tw_push_seg ;;
            "$2") _tw_push_seg; _tw_after="$_tw_rest"; [ "$_tw_bad" -eq 0 ]; return ;;
            *) _tw_seg="$_tw_seg$_tw_c" ;;
        esac
    done
    return 1
}

_tw_push_seg() {
    if [ -z "$_tw_seg" ] && [ "$_tw_quoted" -eq 0 ]; then
        _tw_bad=1
    fi
    case "$_tw_seg" in
        ''|*[!A-Za-z0-9_-]*) _tw_seg="\"$_tw_seg\"" ;;
    esac
    [ "$_tw_nseg" -eq 0 ] && _tw_first="$_tw_seg"
    _tw_path="${_tw_path:+$_tw_path.}$_tw_seg"
    _tw_nseg=$(( _tw_nseg + 1 )); _tw_seg=""; _tw_quoted=0
}

# The name a `[section]` or `[[array of tables]]` header names, into the named
# variable, and `_tw_aot` set for the second kind. Fails when the line is not a
# header. Padding inside the brackets and a comment after them are the
# header's, as the reader takes them, so `[ a . b ] # note` is `a.b`.
_tw_header_of() {
    _tw_trim "$1"; _tw_aot=0
    case "$_tw_s" in
        "[["*) _tw_aot=1; _tw_s="${_tw_s#??}" ;;
        "["*) _tw_s="${_tw_s#?}" ;;
        *) return 1 ;;
    esac
    _tw_path_scan "$_tw_s" "]" || return 1
    if [ "$_tw_aot" -eq 1 ]; then
        case "$_tw_after" in "]"*) _tw_after="${_tw_after#"]"}" ;; *) return 1 ;; esac
    fi
    _tw_trim "$_tw_after"
    case "$_tw_s" in ""|"#"*) ;; *) return 1 ;; esac
    eval "$2=\$_tw_path"
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

# The trailing comment of a value, with the space before it, into `_tw_cmt`,
# empty when there is none. A `#` inside a quoted string is the string's.
_tw_comment_of() {
    _tw_rest="$1"; _tw_q=""; _tw_gap=""; _tw_cmt=""
    while [ -n "$_tw_rest" ]; do
        _tw_c="${_tw_rest%"${_tw_rest#?}"}"; _tw_rest="${_tw_rest#?}"
        if [ -n "$_tw_q" ]; then
            if [ "$_tw_c" = "$_tw_q" ]; then
                _tw_q=""
            elif [ "$_tw_q" = '"' ] && [ "$_tw_c" = '\' ]; then
                _tw_rest="${_tw_rest#?}"
            fi
            continue
        fi
        case "$_tw_c" in
            '"'|"'") _tw_q="$_tw_c"; _tw_gap="" ;;
            " "|"$_TW_TAB") _tw_gap="$_tw_gap$_tw_c" ;;
            "#") _tw_cmt="$_tw_gap#$_tw_rest"; return 0 ;;
            *) _tw_gap="" ;;
        esac
    done
}

# Whether the file holds the key in a shape one line cannot change. Prints why
# and returns 2 when it does, so `toml_set` and `toml_unset` refuse it rather
# than write a file TOML forbids:
#
#   a dotted key made the key or a table above it, so the key is not on a line
#     of its own and a header for its table would define that table twice;
#   the key sits inside an array of tables, where a header names every element
#     at once and a line names one;
#   the key sits inside an inline table, which is one value on one line.
_tw_refusal() {
    _twr_file="$1"; _twr_key="$2"; _twr_verb="$3"; _twr_sect=""; _twr_line=""; _twr_hdr=""
    [ -f "$_twr_file" ] || return 0
    while IFS= read -r _twr_line || [ -n "$_twr_line" ]; do
        if _tw_header_of "$_twr_line" _twr_hdr; then
            _twr_sect="$_twr_hdr"
            if [ "$_tw_aot" -eq 1 ]; then
                case "$_twr_key" in
                    "$_twr_hdr".*)
                        _tw_deny "it is inside the array of tables [[$_twr_hdr]]"
                        return 2 ;;
                esac
            fi
            continue
        fi
        _tw_trim "$_twr_line"
        case "$_tw_s" in ""|"#"*) continue ;; esac
        _tw_path_scan "$_tw_s" "=" || continue
        _twr_at="${_twr_sect:+$_twr_sect.}"
        if [ "$_tw_nseg" -gt 1 ]; then
            case "$_twr_key" in
                "$_twr_at$_tw_first"|"$_twr_at$_tw_first".*)
                    _tw_deny "a dotted key, $_tw_path, defines it or a table above it"
                    return 2 ;;
            esac
        fi
        _tw_trim "$_tw_after"
        case "$_tw_s" in
            "$_TW_LB"*)
                case "$_twr_key" in
                    "$_twr_at$_tw_path".*)
                        _tw_deny "it is inside the inline table $_twr_at$_tw_path"
                        return 2 ;;
                esac ;;
        esac
    done < "$_twr_file"
    return 0
}

_tw_deny() {
    printf 'toml: %s: cannot %s %s: %s\n' "$_twr_file" "$_twr_verb" "$_twr_key" "$1" >&2
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
# Usage: toml_set "file.toml" "section.key" "value" -> returns 2 for a shape one line cannot change
toml_set() {
    _tws_file="$1"; _tws_key="$2"; _tws_value="$3"
    [ -n "$_tws_file" ] && [ -n "$_tws_key" ] || return 1

    _tws_section=""; _tws_leaf="$_tws_key"
    case "$_tws_key" in
        *.*) _tws_section="${_tws_key%.*}"; _tws_leaf="${_tws_key##*.}" ;;
    esac

    _tw_refusal "$_tws_file" "$_tws_key" set || return 2

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
            # `_tw_is_key` leaves the line after its `=` in `_tw_s`.
            _tw_comment_of "${_tw_s#=}"
            printf '%s = %s%s\n' "$_tws_leaf" "$_tws_written" "$_tw_cmt" >> "$_tws_tmp"
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
    str_replace "$_twv" '\' '\\' _twv_esc
    str_replace "$_twv_esc" '"' '\"' _twv_esc
    str_replace "$_twv_esc" "$_TW_NL" '\n' _twv_esc
    str_replace "$_twv_esc" "$_TW_CR" '\r' _twv_esc
    str_replace "$_twv_esc" "$_TW_TAB" '\t' _twv_esc
    str_replace "$_twv_esc" "$_TW_BS" '\b' _twv_esc
    str_replace "$_twv_esc" "$_TW_FF" '\f' _twv_esc
    printf '"%s"' "$_twv_esc"
}

#[pub]
# Remove a key, leaving everything else alone.
#
# A key with no section means one before the first `[header]`. Reading that as
# "no section is open" deleted the key from every section in the file.
# Usage: toml_unset "file.toml" "section.key" -> returns 2 for a shape one line cannot change
toml_unset() {
    _twu_file="$1"; _twu_key="$2"
    [ -f "$_twu_file" ] && [ -n "$_twu_key" ] || return 1

    _twu_section=""; _twu_leaf="$_twu_key"
    case "$_twu_key" in
        *.*) _twu_section="${_twu_key%.*}"; _twu_leaf="${_twu_key##*.}" ;;
    esac

    _tw_refusal "$_twu_file" "$_twu_key" unset || return 2

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
