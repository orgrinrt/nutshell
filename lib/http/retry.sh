#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/http/retry.sh - a failure that may pass on a second try
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Loaded by `lib/http.sh`, which is where a caller gets it from.
#
# A fetch through a proxy meets resets, timeouts and a 503 that the next
# request does not, and an install that fails on one of them fails for nothing.
# So a request is tried again, the same on curl and wget, and what counts as
# worth a second try depends on whether the request may already have been acted on.
#
# GET, HEAD and DELETE are tried again when
#
#   - the answer is 429, 502, 503 or 504, or
#   - there was no answer: a name or connection that failed, a timeout, a
#     connection reset or closed without one.
#
# Any other method (POST, PUT, PATCH) is tried again only where the server did
# nothing with the request: the answer is 429 or 503, or the connection was
# never made (curl 5, 6, 7 and 35, and a wget that failed to resolve, connect or
# shake hands). A reset or a timeout after the request was sent is final for
# them, so a charge is never made twice.
#
# Any other answer is final, 404 and the rest of the 4xx included.
#
#   NUT_HTTP_RETRIES      tries after the first: 3 where unset, 10 at most, 0
#                         turns retrying off
#   NUT_HTTP_RETRY_DELAY  seconds before the next try: 1 where unset, doubling,
#                         never more than 30
#   NUT_HTTP_DEADLINE     seconds after which no further try starts: 120 where
#                         unset, 0 allows the first try only. Each try is also
#                         bounded by HTTP_TIMEOUT, so a call is over soon after
#                         the deadline and never at (tries x HTTP_TIMEOUT).
#
# A `Retry-After` of whole seconds on the answer is waited for where it is
# longer than the delay; one that would end past the deadline ends the call at
# once, since no try could start in time. A date there is not read.
#
# Neither tool is left to retry on its own, so the count means the same on both.
# A request that has a body is tried again as it is.

[ -n "${_NUTSHELL_HTTP_RETRY_SH:-}" ] && return 0
_NUTSHELL_HTTP_RETRY_SH=1

# What the last attempt did: the tool's own exit status, the method it sent,
# whether wget never made the connection, and the `Retry-After` it was told.
_HTTP_TRY_RC=0
_HTTP_TRY_METHOD="GET"
_HTTP_TRY_NOSEND=0
_HTTP_TRY_AFTER=""

# The settings the last `_http_retry_config` read.
_HTTP_RETRY_MAX=3
_HTTP_RETRY_MS=1000
_HTTP_RETRY_DEADLINE_MS=120000

# What `_http_now_ms` read.
_HTTP_NOW=0

# _http_ms_of <seconds> <fallback ms> -> _HTTP_MS, a decimal number of seconds as milliseconds
# A value that is no number, or has more than six whole digits, is the fallback.
_http_ms_of() {
    local d="$1" whole frac
    _HTTP_MS="$2"
    case "$d" in
        ''|*[!0-9.]*|*.*.*|.) return 0 ;;
    esac
    whole="${d%%.*}"; frac=""
    [[ "$d" == *.* ]] && frac="${d#*.}"
    [[ "${#whole}" -gt 6 ]] && return 0
    frac="${frac}000"; frac="${frac:0:3}"
    [[ -z "$whole" ]] && whole=0
    _HTTP_MS=$(( 10#$whole * 1000 + 10#$frac ))
}

# _http_retry_config -> _HTTP_RETRY_MAX, _HTTP_RETRY_MS and _HTTP_RETRY_DEADLINE_MS
_http_retry_config() {
    local n="${NUT_HTTP_RETRIES:-3}"
    case "$n" in ''|*[!0-9]*) n=3 ;; esac
    [[ "${#n}" -gt 3 ]] && n=10
    [[ "$(( 10#$n ))" -gt 10 ]] && n=10
    _HTTP_RETRY_MAX="$(( 10#$n ))"
    _http_ms_of "${NUT_HTTP_RETRY_DELAY:-1}" 1000
    _HTTP_RETRY_MS="$_HTTP_MS"
    _http_ms_of "${NUT_HTTP_DEADLINE:-120}" 120000
    _HTTP_RETRY_DEADLINE_MS="$_HTTP_MS"
}

# _http_now_ms -> _HTTP_NOW, a clock in milliseconds that only goes forward from here
_http_now_ms() {
    local t
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        t="${EPOCHREALTIME/[.,]/}"
        _HTTP_NOW=$(( 10#$t / 1000 ))
    else
        _HTTP_NOW=$(( SECONDS * 1000 ))
    fi
}

# _http_idempotent -> 0 when the last attempt's method may be sent twice
_http_idempotent() {
    case "$_HTTP_TRY_METHOD" in
        GET|HEAD|DELETE) return 0 ;;
    esac
    return 1
}

# _http_transient -> 0 when what the last attempt left is worth another try
_http_transient() {
    case "$_HTTP_LAST_STATUS" in
        429|503) return 0 ;;
        502|504) _http_idempotent; return $? ;;
        '') ;;
        *) return 1 ;;
    esac
    # No answer: the tool's status says whether the request was ever sent.
    #   never connected   curl 5 6 7 35 (name, connection, handshake) and a wget
    #                     whose message says it never connected
    #   maybe sent        curl 18 56 (cut short, reset)   28 (timed out)
    #                     52 55 (empty reply, send failed)   wget 4 otherwise
    case "$_HTTP_CALL_IMPL:$_HTTP_TRY_RC" in
        curl:5|curl:6|curl:7|curl:35) return 0 ;;
        curl:18|curl:28|curl:52|curl:55|curl:56) _http_idempotent; return $? ;;
        wget:4)
            [[ "$_HTTP_TRY_NOSEND" == "1" ]] && return 0
            _http_idempotent; return $? ;;
    esac
    return 1
}

# _http_retry_after <headers> -> _HTTP_TRY_AFTER, whole seconds of the last Retry-After, or empty
# Each answer's header block starts at its status line, so one that came before a redirect is dropped.
_http_retry_after() {
    local line v
    _HTTP_TRY_AFTER=""
    while IFS= read -r line; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in
            HTTP/*) _HTTP_TRY_AFTER="" ;;
            [Rr][Ee][Tt][Rr][Yy]-[Aa][Ff][Tt][Ee][Rr]:*)
                v="${line#*:}"
                v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
                case "$v" in
                    ''|*[!0-9]*) _HTTP_TRY_AFTER="" ;;
                    *) [[ "${#v}" -le 6 ]] && _HTTP_TRY_AFTER="$v" || _HTTP_TRY_AFTER="" ;;
                esac ;;
        esac
    done <<<"$1"
}

# _http_backoff <ms> -> waits that long
_http_backoff() {
    local ms="$1" s
    s="$(( ms / 1000 )).$(printf '%03d' $(( ms % 1000 )))"
    sleep "$s" 2>/dev/null || sleep "$(( (ms + 999) / 1000 ))"
}

# Usage: _http_retrying <attempt> [args...] -> the attempt's own status after the last try
# The attempt leaves `_HTTP_LAST_STATUS`, `_HTTP_LAST_HEADERS`, `_HTTP_TRY_RC`,
# `_HTTP_TRY_NOSEND` and `_HTTP_CALL_IMPL` for `_http_transient` to read, and
# the caller sets `_HTTP_TRY_METHOD` before.
#[pub(super)]
_http_retrying() {
    local n=0 rc wait_ms pause start
    _http_retry_config
    wait_ms="$_HTTP_RETRY_MS"
    _http_now_ms; start="$_HTTP_NOW"
    while :; do
        _HTTP_TRY_NOSEND=0
        "$@"; rc=$?
        [[ "$n" -ge "$_HTTP_RETRY_MAX" ]] && return "$rc"
        _http_transient || return "$rc"
        _http_retry_after "$_HTTP_LAST_HEADERS"
        pause="$wait_ms"
        [[ -n "$_HTTP_TRY_AFTER" && "$(( 10#$_HTTP_TRY_AFTER * 1000 ))" -gt "$pause" ]] \
            && pause="$(( 10#$_HTTP_TRY_AFTER * 1000 ))"
        _http_now_ms
        [[ "$(( _HTTP_NOW - start + pause ))" -ge "$_HTTP_RETRY_DEADLINE_MS" ]] && return "$rc"
        n=$((n + 1))
        _http_backoff "$pause"
        wait_ms=$(( wait_ms * 2 ))
        [[ "$wait_ms" -gt 30000 ]] && wait_ms=30000
    done
}
