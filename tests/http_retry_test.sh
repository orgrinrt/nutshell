#!/usr/bin/env bash
# Tests for what http does with a failure that may pass on a second try.
#
# The server is `nc` on the loopback, answering a scripted sequence (see
# fixtures/http_server.sh), so each test says how many requests the client made
# and not only what it was finally told. Both tools are driven: curl as found,
# and wget by hiding curl, since the module must behave the same on either.
#
# Where `nc` or the second tool is absent a test skips and says why, because a
# test that returned early passed having asserted nothing.

use http deps test
source "${BASH_SOURCE[0]%/*}/fixtures/hide_tools.sh"
source "${BASH_SOURCE[0]%/*}/fixtures/http_server.sh"

# The wait between tries is shortened for every test; the default is whole seconds.
export NUT_HTTP_RETRY_DELAY=0.2
HTTP_TIMEOUT=5

# _want <curl|wget> -> 0 when the test can run with that tool, else skips it
_want() {
    srv_available || { skip "nc is not on this machine, so there is no loopback server"; return 1; }
    if [[ "$1" == "wget" ]]; then
        deps_has wget || { skip "wget is not on this machine"; return 1; }
        _hide_tools curl
        http_detect
        assert_eq "$(http_impl)" "wget" "curl was meant to be hidden"
    else
        deps_has curl || { skip "curl is not on this machine"; return 1; }
        assert_eq "$(http_impl)" "curl"
    fi
    return 0
}

# _begin <behaviour...> -> PORT and DIR set, the server up
_begin() {
    PORT="$(srv_port)"; DIR="$(mktemp -d)"
    srv_start "$PORT" "$DIR" "$@"
}

_end() { srv_stop; rm -rf "$DIR" "${OUT:-}"; }

#[test]
it_retries_a_503_on_a_get_until_the_200_arrives_on_curl() {
    _want curl || return 0
    _begin 503 503 "200:third time"
    http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "200"
    assert_eq "$(http_body)" "third time"
    assert_eq "$(srv_requests "$DIR")" "3"
    _end
}

#[test]
it_retries_a_503_on_a_get_until_the_200_arrives_on_wget() {
    _want wget || return 0
    _begin 503 503 "200:third time"
    http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "200"
    assert_eq "$(http_body)" "third time"
    assert_eq "$(srv_requests "$DIR")" "3"
    _end
}

#[test]
it_retries_a_503_on_a_download_until_the_200_arrives_on_curl() {
    _want curl || return 0
    _begin 503 503 "200:the payload"; OUT="$(mktemp)"
    assert_ok http_download "http://127.0.0.1:$PORT/f" "$OUT"
    assert_eq "$(cat "$OUT")" "the payload"
    assert_eq "$(srv_requests "$DIR")" "3"
    _end
}

#[test]
it_retries_a_503_on_a_download_until_the_200_arrives_on_wget() {
    _want wget || return 0
    _begin 503 503 "200:the payload"; OUT="$(mktemp)"
    assert_ok http_download "http://127.0.0.1:$PORT/f" "$OUT"
    assert_eq "$(cat "$OUT")" "the payload"
    assert_eq "$(srv_requests "$DIR")" "3"
    _end
}

#[test]
it_retries_each_of_429_502_and_504_on_curl() {
    _want curl || return 0
    local s
    for s in 429 502 504; do
        _begin "$s" "200:after $s"
        http_get "http://127.0.0.1:$PORT/x"
        assert_eq "$(http_body)" "after $s"
        assert_eq "$(srv_requests "$DIR")" "2" "status $s"
        _end
    done
}

#[test]
it_retries_each_of_429_502_and_504_on_wget() {
    _want wget || return 0
    local s
    for s in 429 502 504; do
        _begin "$s" "200:after $s"
        http_get "http://127.0.0.1:$PORT/x"
        assert_eq "$(http_body)" "after $s"
        assert_eq "$(srv_requests "$DIR")" "2" "status $s"
        _end
    done
}

#[test]
it_never_retries_a_404_on_curl() {
    _want curl || return 0
    _begin 404 "200:too late"; OUT="$(mktemp)"
    http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "404"
    assert_eq "$(srv_requests "$DIR")" "1"
    _end
    _begin 404 "200:too late"; OUT="$(mktemp)"
    assert_fails http_download "http://127.0.0.1:$PORT/x" "$OUT"
    assert_eq "$(srv_requests "$DIR")" "1"
    _end
}

#[test]
it_never_retries_a_404_on_wget() {
    _want wget || return 0
    _begin 404 "200:too late"; OUT="$(mktemp)"
    http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "404"
    assert_eq "$(srv_requests "$DIR")" "1"
    _end
    _begin 404 "200:too late"; OUT="$(mktemp)"
    assert_fails http_download "http://127.0.0.1:$PORT/x" "$OUT"
    assert_eq "$(srv_requests "$DIR")" "1"
    _end
}

#[test]
it_turns_retrying_off_with_zero_retries_on_curl() {
    _want curl || return 0
    _begin 503 "200:too late"; OUT="$(mktemp)"
    NUT_HTTP_RETRIES=0 http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "503"
    assert_eq "$(srv_requests "$DIR")" "1"
    _end
}

#[test]
it_turns_retrying_off_with_zero_retries_on_wget() {
    _want wget || return 0
    _begin 503 "200:too late"; OUT="$(mktemp)"
    NUT_HTTP_RETRIES=0 http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "503"
    assert_eq "$(srv_requests "$DIR")" "1"
    _end
}

#[test]
it_gives_up_after_the_configured_retries_and_keeps_the_last_answer() {
    _want curl || return 0
    _begin 503 503 503 503 503 503; OUT="$(mktemp)"
    NUT_HTTP_RETRIES=2 http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "503"
    assert_eq "$(srv_requests "$DIR")" "3" "one try and two retries"
    _end
    _begin 503 503 503 503 503 503; OUT="$(mktemp)"
    NUT_HTTP_RETRIES=1 assert_fails http_download "http://127.0.0.1:$PORT/x" "$OUT"
    assert_eq "$(srv_requests "$DIR")" "2" "one try and one retry"
    _end
}

#[test]
it_makes_three_retries_when_nothing_is_configured() {
    _want curl || return 0
    _begin 503 503 503 503 503 503; OUT="$(mktemp)"
    unset NUT_HTTP_RETRIES
    http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "503"
    assert_eq "$(srv_requests "$DIR")" "4"
    _end
}

#[test]
it_retries_a_connection_closed_without_an_answer_on_curl() {
    _want curl || return 0
    _begin reset "200:second try"
    http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_body)" "second try"
    assert_eq "$(srv_requests "$DIR")" "2"
    _end
}

#[test]
it_retries_a_connection_closed_without_an_answer_on_wget() {
    _want wget || return 0
    _begin reset "200:second try"; OUT="$(mktemp)"
    assert_ok http_download "http://127.0.0.1:$PORT/x" "$OUT"
    assert_eq "$(cat "$OUT")" "second try"
    assert_eq "$(srv_requests "$DIR")" "2"
    _end
}

#[test]
it_retries_a_timeout_on_curl() {
    _want curl || return 0
    _begin hang "200:after the wait"
    HTTP_TIMEOUT=1 NUT_HTTP_RETRIES=6 http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_body)" "after the wait"
    _end
}

#[test]
it_retries_a_timeout_on_wget() {
    _want wget || return 0
    _begin hang "200:after the wait"; OUT="$(mktemp)"
    HTTP_TIMEOUT=1 NUT_HTTP_RETRIES=6 assert_ok http_download "http://127.0.0.1:$PORT/x" "$OUT"
    assert_eq "$(cat "$OUT")" "after the wait"
    _end
}

# -----------------------------------------------------------------------------
# A request that is not a GET, HEAD or DELETE is sent once unless the server
# said, or the connection showed, that it did nothing with it.

#[test]
it_sends_a_post_once_when_the_connection_is_closed_without_an_answer_on_curl() {
    _want curl || return 0
    _begin reset 200
    http_post "http://127.0.0.1:$PORT/pay" "charge=100"
    assert_eq "$(srv_requests "$DIR")" "1" "a POST that reached the server was sent again"
    _end
}

#[test]
it_sends_a_post_once_when_the_connection_is_closed_without_an_answer_on_wget() {
    _want wget || return 0
    _begin reset 200
    http_post "http://127.0.0.1:$PORT/pay" "charge=100"
    assert_eq "$(srv_requests "$DIR")" "1" "a POST that reached the server was sent again"
    _end
}

# The server of `hang 200` listens again only after three seconds, so the tries
# of a call that does retry reach the 200 at the third (one second of waiting,
# then two), and the count says whether it did.
#[test]
it_sends_a_put_and_a_patch_once_after_a_timeout_on_curl() {
    _want curl || return 0
    _begin hang 200
    NUT_HTTP_RETRY_DELAY=1 HTTP_TIMEOUT=1 http_put "http://127.0.0.1:$PORT/x" "v=1"
    assert_eq "$(srv_requests "$DIR")" "1" "PUT"
    _end
    _begin hang 200
    NUT_HTTP_RETRY_DELAY=1 HTTP_TIMEOUT=1 http_patch "http://127.0.0.1:$PORT/x" "v=1"
    assert_eq "$(srv_requests "$DIR")" "1" "PATCH"
    _end
}

#[test]
it_sends_a_put_once_after_a_timeout_on_wget() {
    _want wget || return 0
    _begin hang 200
    NUT_HTTP_RETRY_DELAY=1 HTTP_TIMEOUT=1 http_put "http://127.0.0.1:$PORT/x" "v=1"
    assert_eq "$(srv_requests "$DIR")" "1"
    _end
}

#[test]
it_retries_a_post_on_a_503_because_the_server_did_nothing_on_curl() {
    _want curl || return 0
    _begin 503 "200:done"
    http_post "http://127.0.0.1:$PORT/pay" "charge=100"
    assert_eq "$(http_body)" "done"
    assert_eq "$(srv_requests "$DIR")" "2"
    assert_contains "$(srv_request "$DIR" 2)" "charge=100" "the retry lost its body"
    _end
}

#[test]
it_retries_a_post_on_a_503_because_the_server_did_nothing_on_wget() {
    _want wget || return 0
    _begin 503 "200:done"
    http_post "http://127.0.0.1:$PORT/pay" "charge=100"
    assert_eq "$(http_body)" "done"
    assert_eq "$(srv_requests "$DIR")" "2"
    _end
}

#[test]
it_retries_a_post_on_a_429_on_curl() {
    _want curl || return 0
    _begin 429 "200:done"
    http_post "http://127.0.0.1:$PORT/pay" "charge=100"
    assert_eq "$(srv_requests "$DIR")" "2"
    _end
}

#[test]
it_sends_a_post_once_on_a_502_and_a_504_on_curl() {
    _want curl || return 0
    local s
    for s in 502 504; do
        _begin "$s" "200:done"
        http_post "http://127.0.0.1:$PORT/pay" "charge=100"
        assert_eq "$(srv_requests "$DIR")" "1" "status $s"
        _end
    done
}

#[test]
it_still_retries_a_delete_after_a_reset_on_curl() {
    _want curl || return 0
    _begin reset "200:done"
    http_delete "http://127.0.0.1:$PORT/x"
    assert_eq "$(srv_requests "$DIR")" "2"
    _end
}

# A server that is not there yet is a connection never made, so even a POST
# is tried again until it is.
_serve_late() {
    local port="$1" dir="$2"; shift 2
    mkdir -p "$dir"
    ( sleep 0.5; srv_start "$port" "$dir" "$@" ) &
    _SRV_PID=$!; _SRV_PORT="$port"
}

#[test]
it_retries_a_post_while_the_connection_is_refused_on_curl() {
    _want curl || return 0
    PORT="$(srv_port)"; DIR="$(mktemp -d)"
    _serve_late "$PORT" "$DIR" "200:arrived"
    NUT_HTTP_RETRIES=5 http_post "http://127.0.0.1:$PORT/pay" "charge=100"
    assert_eq "$(http_body)" "arrived"
    assert_eq "$(srv_requests "$DIR")" "1"
    _end
}

#[test]
it_retries_a_post_while_the_connection_is_refused_on_wget() {
    _want wget || return 0
    PORT="$(srv_port)"; DIR="$(mktemp -d)"
    _serve_late "$PORT" "$DIR" "200:arrived"
    NUT_HTTP_RETRIES=5 http_post "http://127.0.0.1:$PORT/pay" "charge=100"
    assert_eq "$(http_body)" "arrived"
    assert_eq "$(srv_requests "$DIR")" "1"
    _end
}

# What `_http_transient` makes of a status, with the method fixed: the codes
# below are curl's own (5 6 7 35 never connected; 18 28 52 55 56 after the request
# may have been sent).
#[test]
it_tells_by_curl_status_whether_a_post_may_be_sent_again() {
    local rc
    _HTTP_CALL_IMPL=curl; _HTTP_LAST_STATUS=""; _HTTP_TRY_METHOD=POST
    for rc in 5 6 7 35; do
        _HTTP_TRY_RC=$rc
        assert_ok _http_transient
    done
    for rc in 18 28 52 55 56; do
        _HTTP_TRY_RC=$rc
        assert_refused assert_ok _http_transient
    done
}

#[test]
it_tells_by_curl_status_whether_a_get_may_be_sent_again() {
    local rc
    _HTTP_CALL_IMPL=curl; _HTTP_LAST_STATUS=""; _HTTP_TRY_METHOD=GET
    for rc in 5 6 7 18 28 35 52 55 56; do
        _HTTP_TRY_RC=$rc
        assert_ok _http_transient
    done
}

# -----------------------------------------------------------------------------
# Retry-After, the overall deadline and the cap on the count

# _seconds_of <command...> -> whole seconds the command took, in ELAPSED
_seconds_of() {
    local t0=$SECONDS
    "$@"
    ELAPSED=$((SECONDS - t0))
}

#[test]
it_waits_for_a_429s_retry_after_on_curl() {
    _want curl || return 0
    _begin after:2:429 "200:done"
    _seconds_of http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_body)" "done"
    assert_ok test "$ELAPSED" -ge 2
    _end
}

#[test]
it_waits_for_a_429s_retry_after_on_wget() {
    _want wget || return 0
    _begin after:2:429 "200:done"
    _seconds_of http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_body)" "done"
    assert_ok test "$ELAPSED" -ge 2
    _end
}

#[test]
it_waits_for_a_429s_retry_after_on_a_download_on_curl() {
    _want curl || return 0
    _begin after:2:429 "200:the payload"; OUT="$(mktemp)"
    _seconds_of http_download "http://127.0.0.1:$PORT/f" "$OUT"
    assert_eq "$(cat "$OUT")" "the payload"
    assert_ok test "$ELAPSED" -ge 2
    _end
}

#[test]
it_waits_for_a_429s_retry_after_on_a_download_on_wget() {
    _want wget || return 0
    _begin after:2:429 "200:the payload"; OUT="$(mktemp)"
    _seconds_of http_download "http://127.0.0.1:$PORT/f" "$OUT"
    assert_eq "$(cat "$OUT")" "the payload"
    assert_ok test "$ELAPSED" -ge 2
    _end
}

#[test]
it_does_not_wait_for_a_retry_after_that_passes_the_deadline() {
    _want curl || return 0
    _begin after:100:429 "200:too late"
    NUT_HTTP_DEADLINE=3 _seconds_of http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "429"
    assert_eq "$(srv_requests "$DIR")" "1"
    assert_ok test "$ELAPSED" -lt 4
    _end
}

#[test]
it_starts_no_attempt_after_the_deadline_on_curl() {
    _want curl || return 0
    _begin 503 503 503 503 503 503
    # tries would begin at 0, 1, 3 and 7 seconds; the fourth is past 4
    NUT_HTTP_RETRY_DELAY=1 NUT_HTTP_RETRIES=10 NUT_HTTP_DEADLINE=4 http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "503"
    assert_eq "$(srv_requests "$DIR")" "3"
    _end
}

#[test]
it_starts_no_attempt_after_the_deadline_on_wget() {
    _want wget || return 0
    _begin 503 503 503 503 503 503
    NUT_HTTP_RETRY_DELAY=1 NUT_HTTP_RETRIES=10 NUT_HTTP_DEADLINE=4 http_get "http://127.0.0.1:$PORT/x"
    assert_eq "$(http_status)" "503"
    assert_eq "$(srv_requests "$DIR")" "3"
    _end
}

#[test]
it_caps_the_retries_at_ten() {
    local v
    for v in 11 1000 99999999999999999999; do
        NUT_HTTP_RETRIES="$v" _http_retry_config
        assert_eq "$_HTTP_RETRY_MAX" "10" "NUT_HTTP_RETRIES=$v"
    done
    NUT_HTTP_RETRIES=10 _http_retry_config
    assert_eq "$_HTTP_RETRY_MAX" "10"
    NUT_HTTP_RETRIES=4 _http_retry_config
    assert_eq "$_HTTP_RETRY_MAX" "4"
}

#[test]
it_reads_the_deadline_in_seconds_with_two_minutes_where_unset() {
    unset NUT_HTTP_DEADLINE
    _http_retry_config
    assert_eq "$_HTTP_RETRY_DEADLINE_MS" "120000"
    NUT_HTTP_DEADLINE=7 _http_retry_config
    assert_eq "$_HTTP_RETRY_DEADLINE_MS" "7000"
    NUT_HTTP_DEADLINE=soon _http_retry_config
    assert_eq "$_HTTP_RETRY_DEADLINE_MS" "120000" "a value that is no number is taken as unset"
}
