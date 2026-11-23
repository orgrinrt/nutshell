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

# -----------------------------------------------------------------------------
# An argument the module does not take is refused, never handed to the tool,
# where a curl flag means something else to wget: `-o` writes wget's log, `-k`
# converts links, `-L` is relative, `-i` reads a list of urls, `-e` runs a
# command from `.wgetrc`.

source "${BASH_SOURCE[0]%/*}/fixtures/hide_tools.sh"
source "${BASH_SOURCE[0]%/*}/fixtures/http_server.sh"

# _tool <curl|wget> -> 0 when the test can run with that tool, else skips it
_tool() {
    _need_nc || return 1
    if [[ "$1" == "wget" ]]; then
        deps_has wget || { skip "wget is not on this machine"; return 1; }
        _hide_tools curl
        http_detect
        assert_eq "$(http_impl)" "wget" "curl was meant to be hidden"
    else
        deps_has curl || { skip "curl is not on this machine"; return 1; }
        assert_eq "$(http_impl)" "curl"
    fi
}

# _refuses_arg <fn> <arg...> -> the call made with those trailing arguments, nothing sent
_refuses_arg() {
    local fn="$1"; shift
    local port dir out rc f; port="$(srv_port)"; dir="$(mktemp -d)"; f="$(mktemp -u)"
    srv_start "$port" "$dir" 200
    if [[ "$fn" == "http_upload" ]]; then
        out="$(http_upload "http://127.0.0.1:$port/u" "$dir/req.1" file "$@" 2>&1)"; rc=$?
    else
        out="$(http_download "http://127.0.0.1:$port/f" "$f" "$@" 2>&1)"; rc=$?
    fi
    assert_eq "$rc" "2" "$fn $*"
    assert_contains "$out" "${1:-}" "the refusal does not name the argument"
    assert_eq "$(srv_requests "$dir")" "0" "the request was made though an argument was refused"
    assert_empty "$(ls "$f" 2>/dev/null)" "$fn wrote the output file after refusing an argument"
    rm -f "$f"
    srv_stop; rm -rf "$dir"
}

#[test]
it_refuses_an_unknown_argument_to_a_download_on_curl() {
    _tool curl || return 0
    local a
    for a in -o -k -L -i -e --output; do _refuses_arg http_download "$a"; done
}

#[test]
it_refuses_an_unknown_argument_to_a_download_on_wget() {
    _tool wget || return 0
    local a
    for a in -o -k -L -i -e --output; do _refuses_arg http_download "$a"; done
}

#[test]
it_refuses_an_unknown_argument_to_an_upload_on_curl() {
    _tool curl || return 0
    local a
    for a in -o -k -F --output; do _refuses_arg http_upload "$a"; done
}

#[test]
it_refuses_an_unknown_argument_to_an_upload_on_wget() {
    _tool wget || return 0
    local a
    for a in -o -k -L; do _refuses_arg http_upload "$a"; done
}

#[test]
it_still_takes_the_modules_own_options_on_a_download_on_curl() {
    _tool curl || return 0
    local port dir out; port="$(srv_port)"; dir="$(mktemp -d)"; out="$(mktemp)"
    srv_start "$port" "$dir" "200:the payload"
    assert_ok http_download "http://127.0.0.1:$port/f" "$out" --header "X-Probe: alpha"
    assert_eq "$(cat "$out")" "the payload"
    assert_contains "$(srv_request "$dir" 1)" "X-Probe: alpha"
    srv_stop; rm -rf "$dir" "$out"
}

#[test]
it_still_takes_the_modules_own_options_on_a_download_on_wget() {
    _tool wget || return 0
    local port dir out; port="$(srv_port)"; dir="$(mktemp -d)"; out="$(mktemp)"
    srv_start "$port" "$dir" "200:the payload"
    assert_ok http_download "http://127.0.0.1:$port/f" "$out" --header "X-Probe: alpha"
    assert_eq "$(cat "$out")" "the payload"
    assert_contains "$(srv_request "$dir" 1)" "X-Probe: alpha"
    srv_stop; rm -rf "$dir" "$out"
}
