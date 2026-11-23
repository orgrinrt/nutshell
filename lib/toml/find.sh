#!/usr/bin/env bash
# =============================================================================
# nutshell/toml/find.sh - Which of many TOML files holds a value
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# A registry kept as one TOML file per record is asked for the file whose `id`
# is a value, over thousands of files. Parsing each is too slow for that, so a
# file is first scanned as text for the value and parsed only where it is there.
# The scan can only rule a file out, never in: the reader decides, so a value
# inside a comment or under another key is rejected by the parse.

[ -n "${_NUTSHELL_TOML_FIND_SH:-}" ] && return 0
_NUTSHELL_TOML_FIND_SH=1

use super::toml

# The values the reader gives otherwise than the file spells them: a number
# written with underscores, a sign or another base, and a date or time given
# with its separator and zone letter in upper case.
_TOML_RE_FIND_NUM='^[+-]?[0-9]'
_TOML_RE_FIND_DATE='^[0-9]{4}-[0-9]{2}-[0-9]{2}'
_TOML_RE_FIND_TIME='^[0-9]{2}:[0-9]{2}'

#[pub]
# Print the files in which a key holds a value, in the order they were given.
#
# The key is a path, as `toml_get` takes one, and the value is the text
# `toml_get` prints for it, so `toml_find id T-4 *.toml` names the files with
# `id = "T-4"`, however the file spells the string, and `toml_find n 255` names
# one with `n = 0xFF`. A file that is not there is not a match.
#
# A file is first scanned as text, and kept when it holds the value's text or any
# backslash, since an escape can spell any character. A number is also kept when
# it holds an underscore, a plus or a base prefix, and a date or a time is
# scanned for the part a file cannot spell otherwise, so the scan only ever rules
# a file out. A candidate the reader refuses is named on stderr and makes the
# return 2, whatever else matched; a file the scan ruled out is not parsed and so
# not checked.
# Usage: toml_find id T-4 tickets/*.toml -> prints the matching files; returns 1 when none match, 2 when a candidate is not TOML
toml_find() {
    local key="${1:-}" want="${2-}" needle f c scan=1 num=0 rc=0 found=0
    [[ -n "$key" ]] || return 1
    shift 2 || return 1
    # No text to scan for where it is empty, or spans lines, which a file may
    # spell with carriage returns or a trailing backslash.
    [[ -n "$want" && "$want" != *$'\n'* && "$want" != *$'\r'* ]] || scan=0
    needle="$want"
    if [[ "$want" =~ $_TOML_RE_FIND_DATE ]]; then needle="${want:0:10}"
    elif [[ "$want" =~ $_TOML_RE_FIND_TIME ]]; then needle="${want%%Z*}"
    elif [[ "$want" =~ $_TOML_RE_FIND_NUM ]]; then num=1
    fi
    for f in "$@"; do
        [[ -f "$f" && -r "$f" ]] || continue
        if (( scan )); then
            c=""
            IFS= read -r -d '' c < "$f"
            [[ "$c" == *"$needle"* || "$c" == *'\'* ]] || {
                (( num )) && [[ "$c" == *[_+]* || "$c" == *0[xob]* ]] || continue
            }
        fi
        _toml_value "$f" "$key"
        case $? in
            0) [[ "$_tx_out" == "$want" ]] && { printf '%s\n' "$f"; found=1; } ;;
            2) rc=2 ;;
        esac
    done
    (( rc )) && return "$rc"
    (( found ))
}
