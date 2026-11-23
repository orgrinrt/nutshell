#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/http/opts.sh - the options an http call takes, per tool
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Loaded by `lib/http.sh`, which is where a caller gets it from.
#
# A caller says what it wants and the module says it to whichever of curl and
# wget it found, so no script passes one tool's flag and meets the other:
#
#   --header 'Name: value'      an extra request header, also `-H` as before
#                               (wget reads `-H` as span-hosts, so it is read
#                               here and never handed on)
#   --headers-from <src>        header lines read from stdin (`-`), a file or a
#                               file descriptor, for a header that is a secret.
#                               They go to curl as a config on its stdin and
#                               never reach a command line. Wget has no way to
#                               take them without one, so a call that has them
#                               goes to curl, or is refused with status 2.
#   --body-file <f>             the request body, from a file, for POST and PUT
#   --content-type <t>          the Content-Type of that body
#   --insecure                  TLS is not verified, for this call alone. It is
#                               a test-only escape, for a local self-signed host.
#
# Whatever else follows the url of a request is handed to the tool as it was,
# and `http_download` and `http_upload` refuse it.

[ -n "${_NUTSHELL_HTTP_OPTS_SH:-}" ] && return 0
_NUTSHELL_HTTP_OPTS_SH=1

use deps

# What the last parse found.
_HTTP_O_HEADERS=""
_HTTP_O_SECRET=""
_HTTP_O_HAS_SECRET=0
_HTTP_O_BODY_FILE=""
_HTTP_O_CTYPE=""
_HTTP_O_INSECURE=0
_HTTP_O_REST=()

# What `_http_opts_args` made of it for the tool this call uses.
_HTTP_X_ARGS=()

# The tool this call uses, and where it is.
_HTTP_CALL_IMPL=""
_HTTP_CALL_BIN=""

# Usage: _http_opts_fail <what> -> status 2, the reason said on stderr and kept as the body
#[pub(super)]
_http_opts_fail() {
    _HTTP_LAST_STATUS=""
    _HTTP_LAST_HEADERS=""
    _HTTP_LAST_BODY="http: $1"
    printf '%s\n' "$_HTTP_LAST_BODY" >&2
    return 2
}

# Usage: _http_is_option <arg> -> 0 when the module takes it, for a body told from an option
#[pub(super)]
_http_is_option() {
    case "$1" in
        --header|--header=*|-H|--headers-from|--headers-from=*) return 0 ;;
        --body-file|--body-file=*|--content-type|--content-type=*|--insecure) return 0 ;;
    esac
    return 1
}

# _http_header_ok <line> -> 0 when it is one header line: a name, a colon, no line break
_http_header_ok() {
    case "$1" in
        *$'\n'*|*$'\r'*|:*) return 1 ;;
        *:*) return 0 ;;
    esac
    return 1
}

# Whether the caller was tracing, for `_http_xtrace_restore`.
_HTTP_XTRACE=0

# _http_xtrace_off -> `set -x` off, and whether it was on kept
# A trace prints every expansion, so a line that holds a secret header is
# never run with it on. The headers are tested through `_HTTP_O_HAS_SECRET`.
_http_xtrace_off() {
    case $- in
        *x*) _HTTP_XTRACE=1; set +x ;;
        *) _HTTP_XTRACE=0 ;;
    esac
}

# _http_xtrace_restore -> `set -x` back on where `_http_xtrace_off` found it on
_http_xtrace_restore() {
    if [[ "$_HTTP_XTRACE" == "1" ]]; then set -x; fi
    return 0
}

# _http_opts_read_lines -> header lines from stdin into _HTTP_O_SECRET, untraced
_http_opts_read_lines() {
    local rc
    _http_xtrace_off
    _http_opts_read_lines_quiet; rc=$?
    _http_xtrace_restore
    return $rc
}

# A bad line is named by its number and never quoted, since it may be the secret.
_http_opts_read_lines_quiet() {
    local line n=0 got=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        line="${line%$'\r'}"
        [[ -z "$line" ]] && continue
        _http_header_ok "$line" || { _http_opts_fail "--headers-from line $n is not a header"; return 2; }
        _HTTP_O_SECRET+="${_HTTP_O_SECRET:+$'\n'}$line"
        got=1
        _HTTP_O_HAS_SECRET=1
    done
    [[ $got -eq 1 ]] || { _http_opts_fail "--headers-from gave no header lines"; return 2; }
}

# _http_opts_take <option> <value> -> the option recorded, or status 2
_http_opts_take() {
    local v="$2"
    case "$1" in
        --header|-H)
            _http_header_ok "$v" || { _http_opts_fail "$1 wants 'Name: value'"; return 2; }
            _HTTP_O_HEADERS+="${_HTTP_O_HEADERS:+$'\n'}$v" ;;
        --headers-from)
            if [[ "$v" == "-" ]]; then
                _http_opts_read_lines
            else
                [[ -r "$v" ]] || { _http_opts_fail "--headers-from cannot read $v"; return 2; }
                _http_opts_read_lines <"$v"
            fi ;;
        --body-file)
            [[ -f "$v" && -r "$v" ]] || { _http_opts_fail "--body-file cannot read $v"; return 2; }
            _HTTP_O_BODY_FILE="$v" ;;
        --content-type)
            _http_header_ok "Content-Type: $v" && [[ -n "$v" ]] \
                || { _http_opts_fail "--content-type wants a media type"; return 2; }
            _HTTP_O_CTYPE="$v" ;;
    esac
}

# _http_opts_parse <args...> -> the module's options taken, the rest in _HTTP_O_REST
_http_opts_parse() {
    _HTTP_O_HEADERS=""; _HTTP_O_SECRET=""; _HTTP_O_HAS_SECRET=0; _HTTP_O_BODY_FILE=""
    _HTTP_O_CTYPE=""; _HTTP_O_INSECURE=0; _HTTP_O_REST=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --header|-H|--headers-from|--body-file|--content-type)
                [[ $# -ge 2 ]] || { _http_opts_fail "$1 needs a value"; return 2; }
                _http_opts_take "$1" "$2" || return 2
                shift 2 ;;
            --header=*|--headers-from=*|--body-file=*|--content-type=*)
                _http_opts_take "${1%%=*}" "${1#*=}" || return 2
                shift ;;
            --insecure) _HTTP_O_INSECURE=1; shift ;;
            *) _HTTP_O_REST+=("$1"); shift ;;
        esac
    done
}

# _http_opts_pick -> _HTTP_CALL_IMPL and _HTTP_CALL_BIN for this call, or status 2
# Curl for a call with a secret header even where the module sits on wget.
_http_opts_pick() {
    _HTTP_CALL_IMPL="$_HTTP_IMPL"
    if [[ "$_HTTP_O_HAS_SECRET" == "1" && "$_HTTP_CALL_IMPL" != "curl" ]] && deps_has curl; then
        _HTTP_CALL_IMPL="curl"
    fi
    if [[ "$_HTTP_CALL_IMPL" == "curl" ]]; then
        _HTTP_CALL_BIN="${_TOOL_PATH_curl}"
    else
        if [[ "$_HTTP_O_HAS_SECRET" == "1" ]]; then
            _http_opts_fail "a header read with --headers-from cannot go to wget without being on its command line, and curl is not on this machine"
            return 2
        fi
        _HTTP_CALL_BIN="${_TOOL_PATH_wget}"
    fi
}

# _http_opts_args -> _HTTP_X_ARGS, the options written the way _HTTP_CALL_IMPL reads them
_http_opts_args() {
    _HTTP_X_ARGS=()
    local h
    while IFS= read -r h; do
        [[ -z "$h" ]] && continue
        if [[ "$_HTTP_CALL_IMPL" == "curl" ]]; then _HTTP_X_ARGS+=(-H "$h"); else _HTTP_X_ARGS+=("--header=$h"); fi
    done <<<"$_HTTP_O_HEADERS"
    if [[ -n "$_HTTP_O_CTYPE" ]]; then
        if [[ "$_HTTP_CALL_IMPL" == "curl" ]]; then
            _HTTP_X_ARGS+=(-H "Content-Type: $_HTTP_O_CTYPE")
        else
            _HTTP_X_ARGS+=("--header=Content-Type: $_HTTP_O_CTYPE")
        fi
    fi
    if [[ -n "$_HTTP_O_BODY_FILE" ]]; then
        if [[ "$_HTTP_CALL_IMPL" == "curl" ]]; then
            _HTTP_X_ARGS+=(--data-binary "@$_HTTP_O_BODY_FILE")
        else
            _HTTP_X_ARGS+=("--body-file=$_HTTP_O_BODY_FILE")
        fi
    fi
    if [[ "$_HTTP_O_INSECURE" == "1" ]]; then
        if [[ "$_HTTP_CALL_IMPL" == "curl" ]]; then _HTTP_X_ARGS+=(-k); else _HTTP_X_ARGS+=(--no-check-certificate); fi
    fi
    return 0
}

# _http_opts_curl_config -> the secret headers as a curl config, on stdout
# Backslash and quote are escaped the way curl's config reads them.
_http_opts_curl_config() {
    local h
    while IFS= read -r h; do
        [[ -z "$h" ]] && continue
        h="${h//\\/\\\\}"
        h="${h//\"/\\\"}"
        printf 'header = "%s"\n' "$h"
    done <<<"$_HTTP_O_SECRET"
}

# Usage: _http_curl_run <curl args...> -> curl's status; the secret headers on its stdin
#[pub(super)]
_http_curl_run() {
    if [[ "$_HTTP_O_HAS_SECRET" == "1" ]]; then
        # the config is written in a subshell with tracing off, the tool itself traced
        ( set +x; _http_opts_curl_config ) | "$_HTTP_CALL_BIN" -K - "$@"
    else
        "$_HTTP_CALL_BIN" "$@"
    fi
}

# Usage: _http_no_rest <caller> -> status 2 naming the first argument the module does not take
# For a call that has no business handing a tool its flags, where one tool's
# flag means another thing to the other: wget reads `-o` as its log file, `-k`
# as convert links, `-L` as relative, `-i` as a list of urls and `-e` as a command.
#[pub(super)]
_http_no_rest() {
    [[ ${#_HTTP_O_REST[@]} -eq 0 ]] && return 0
    _http_opts_fail "$1 does not take the argument ${_HTTP_O_REST[0]}, only the options of http/opts"
}

# Usage: _http_prepare <data> <args...> -> options taken, tool picked and written for it, or status 2
#[pub(super)]
_http_prepare() {
    local data="$1"; shift
    _http_opts_parse "$@" || return 2
    if [[ -n "$data" && -n "$_HTTP_O_BODY_FILE" ]]; then
        _http_opts_fail "--body-file and inline data both given, and a request has one body"
        return 2
    fi
    _http_opts_pick || return 2
    _http_opts_args
}
