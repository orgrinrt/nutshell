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
