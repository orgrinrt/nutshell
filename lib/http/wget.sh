#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/http/wget.sh - what wget's stderr says about an attempt
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Loaded by `lib/http.sh`, which is where a caller gets it from.
#
# Wget writes the response headers (`-S`) and its own messages (`-nv`) to
# stderr and the body to stdout. Read apart from the body, stderr gives the
# status and headers of the answer and, where there was none, whether the
# connection was ever made: its exit status 4 covers a name that did not
# resolve and a reset after the request was sent alike, and `http/retry.sh`
# must tell them apart to know whether a POST may be sent again.

[ -n "${_NUTSHELL_HTTP_WGET_SH:-}" ] && return 0
_NUTSHELL_HTTP_WGET_SH=1

# Usage: _http_wget_parse_err <stderr text> -> _HTTP_LAST_STATUS, _HTTP_LAST_HEADERS and _HTTP_TRY_NOSEND
# The header block is kept as it was before the body was told apart from it:
# a status line with its indent, the rest with the indent taken off.
#[pub(super)]
_http_wget_parse_err() {
    local line
    _HTTP_LAST_HEADERS=""
    _HTTP_LAST_STATUS=""
    _HTTP_TRY_NOSEND=0
    while IFS= read -r line; do
        case "$line" in
            "  HTTP/"*)
                _HTTP_LAST_HEADERS+="$line"$'\n'
                if [[ "$line" =~ HTTP/[0-9.]+" "([0-9]+) ]]; then
                    _HTTP_LAST_STATUS="${BASH_REMATCH[1]}"
                fi ;;
            "  "*) _HTTP_LAST_HEADERS+="${line#  }"$'\n'
                ;;
            # Messages of a connection that was never made, with no request sent.
            failed:*|*"unable to resolve host"*|*"Unable to establish SSL"*)
                _HTTP_TRY_NOSEND=1 ;;
        esac
    done <<<"$1"
}
