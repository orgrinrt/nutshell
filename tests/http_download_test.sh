#!/usr/bin/env bash
# Tests for downloading a file, against a one-shot server on the loopback so
# the assertions say what curl does with a status rather than what a remote
# host happened to answer.
#
# The server is `nc`. Where it is absent there is nothing to download from, and
# a test that returned early passed having asserted nothing, so each one skips
# and says why.

use http deps test

# Answers one request with the given status line and body, then exits.
serve_once() {
    local port="$1" status="$2" body="$3"
    printf 'HTTP/1.1 %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
        "$status" "${#body}" "$body" | nc -l 127.0.0.1 "$port" >/dev/null 2>&1 &
    sleep 0.3
}

free_port() {
    printf '%s' "$(( 20000 + RANDOM % 20000 ))"
}

# _need_nc -> 0 when there is a server to talk to, else the test is skipped
_need_nc() {
    deps_has nc && return 0
    skip "nc is not on this machine, so there is no loopback server to download from"
    return 1
}

#[test]
it_saves_what_a_success_answers() {
    _need_nc || return 0
    local port out; port="$(free_port)"; out="$(mktemp)"
    serve_once "$port" "200 OK" "the payload"
    assert_ok http_download "http://127.0.0.1:$port/file" "$out"
    assert_eq "$(cat "$out")" "the payload"
    rm -f "$out"
}

#[test]
it_refuses_an_error_page() {
    _need_nc || return 0
    local port out; port="$(free_port)"; out="$(mktemp)"
    serve_once "$port" "404 Not Found" "<html>not here</html>"
    assert_fails http_download "http://127.0.0.1:$port/missing" "$out"
    rm -f "$out"
}
