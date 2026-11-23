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
# So a request is tried again, the same on curl and wget, when
#
#   - the answer is 429, 502, 503 or 504, or
#   - there was no answer: a name or connection that failed, a timeout, a
#     connection reset or closed without one.
#
# Any other answer is final, 404 and the rest of the 4xx included. The tries
# are the first and then `NUT_HTTP_RETRIES` more (3 where unset, 0 turns it
# off), the wait before the next one `NUT_HTTP_RETRY_DELAY` seconds (1 where
# unset) and doubling, never more than 30. Neither tool is left to retry on its
# own, so the count means the same on both.
#
# A request that has a body is tried again as it is. A 503 or a reset that came
# before the server did anything is the case this is for, and a caller whose
# POST must not be sent twice sets `NUT_HTTP_RETRIES=0` for that call.

[ -n "${_NUTSHELL_HTTP_RETRY_SH:-}" ] && return 0
_NUTSHELL_HTTP_RETRY_SH=1

# What the last attempt did: the tool's own exit status.
_HTTP_TRY_RC=0

# The settings the last `_http_retry_config` read.
_HTTP_RETRY_MAX=3
_HTTP_RETRY_MS=1000

# _http_retry_config -> _HTTP_RETRY_MAX and _HTTP_RETRY_MS, a value that is no number taken as unset
_http_retry_config() {
    local n="${NUT_HTTP_RETRIES:-3}" d="${NUT_HTTP_RETRY_DELAY:-1}" whole frac
    case "$n" in ''|*[!0-9]*) n=3 ;; esac
    _HTTP_RETRY_MAX="$n"
    case "$d" in
        ''|*[!0-9.]*|*.*.*|.) d=1 ;;
    esac
    whole="${d%%.*}"; frac=""
    [[ "$d" == *.* ]] && frac="${d#*.}"
    frac="${frac}000"; frac="${frac:0:3}"
    [[ -z "$whole" ]] && whole=0
    _HTTP_RETRY_MS=$(( 10#$whole * 1000 + 10#$frac ))
}

# _http_transient -> 0 when what the last attempt left is worth another try
_http_transient() {
    case "$_HTTP_LAST_STATUS" in
        429|502|503|504) return 0 ;;
        '') ;;
        *) return 1 ;;
    esac
    # No answer: the tool's status says whether it was the network.
    #   curl 5 6 7   name or connection failed       18 56   cut short or reset
    #   curl 28      timed out                       35      handshake dropped
    #   curl 52 55   empty reply, send failed        wget 4  network failure
    case "$_HTTP_CALL_IMPL:$_HTTP_TRY_RC" in
        curl:5|curl:6|curl:7|curl:18|curl:28|curl:35|curl:52|curl:55|curl:56) return 0 ;;
        wget:4) return 0 ;;
    esac
    return 1
}

# _http_backoff <ms> -> waits that long
_http_backoff() {
    local ms="$1" s
    s="$(( ms / 1000 )).$(printf '%03d' $(( ms % 1000 )))"
    sleep "$s" 2>/dev/null || sleep "$(( (ms + 999) / 1000 ))"
}

# Usage: _http_retrying <attempt> [args...] -> the attempt's own status after the last try
# The attempt leaves `_HTTP_LAST_STATUS`, `_HTTP_TRY_RC` and `_HTTP_CALL_IMPL` for
# `_http_transient` to read.
#[pub(super)]
_http_retrying() {
    local n=0 rc wait_ms
    _http_retry_config
    wait_ms="$_HTTP_RETRY_MS"
    while :; do
        "$@"; rc=$?
        [[ "$n" -ge "$_HTTP_RETRY_MAX" ]] && return "$rc"
        _http_transient || return "$rc"
        n=$((n + 1))
        _http_backoff "$wait_ms"
        wait_ms=$(( wait_ms * 2 ))
        [[ "$wait_ms" -gt 30000 ]] && wait_ms=30000
    done
}
