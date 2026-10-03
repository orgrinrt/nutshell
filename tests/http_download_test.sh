#!/usr/bin/env bash
# Tests for downloading a file, against a one-shot server on the loopback so
# the assertions say what curl does with a status rather than what a remote
# host happened to answer.

use http test

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

#[test]
it_saves_what_a_success_answers() {
    command -v nc >/dev/null 2>&1 || return 0
    local port out; port="$(free_port)"; out="$(mktemp)"
    serve_once "$port" "200 OK" "the payload"
    assert_ok http_download "http://127.0.0.1:$port/file" "$out"
    assert_eq "$(cat "$out")" "the payload"
    rm -f "$out"
}

#[test]
it_refuses_an_error_page() {
    command -v nc >/dev/null 2>&1 || return 0
    local port out; port="$(free_port)"; out="$(mktemp)"
    serve_once "$port" "404 Not Found" "<html>not here</html>"
    assert_fails http_download "http://127.0.0.1:$port/missing" "$out"
    rm -f "$out"
}
