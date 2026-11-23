#!/usr/bin/env bash
# Tests for the options a caller gives an http call so that it never has to pass
# a tool's own flags: `--header`, `--headers-from`, `--body-file` with
# `--content-type`, and `--insecure`.
#
# The server saves each request whole (fixtures/http_server.sh), so a test reads
# what went on the wire. A secret header is also looked for on the command line
# of the running tool, with a plain header as the control that shows the look can
# see a command line at all.
#
# Where `nc`, `openssl` or the second tool is absent a test skips and says why.

use http deps test api
source "${BASH_SOURCE[0]%/*}/fixtures/hide_tools.sh"
source "${BASH_SOURCE[0]%/*}/fixtures/http_server.sh"

export NUT_HTTP_RETRY_DELAY=0.2
HTTP_TIMEOUT=5
ROOT_DIR="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

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

_begin() { PORT="$(srv_port)"; DIR="$(mktemp -d)"; srv_start "$PORT" "$DIR" "$@"; }
_end() { srv_stop; rm -rf "$DIR" "${TMPF:-}"; }

# -----------------------------------------------------------------------------
# --header

#[test]
it_sends_headers_given_as_options_on_curl() {
    _want curl || return 0
    _begin 200
    http_get "http://127.0.0.1:$PORT/x" --header "X-Probe: alpha" --header "X-Other: beta"
    assert_ok http_ok
    local req; req="$(srv_request "$DIR" 1)"
    assert_contains "$req" "X-Probe: alpha"
    assert_contains "$req" "X-Other: beta"
    _end
}

#[test]
it_sends_headers_given_as_options_on_wget() {
    _want wget || return 0
    _begin 200
    http_get "http://127.0.0.1:$PORT/x" --header "X-Probe: alpha" --header "X-Other: beta"
    assert_ok http_ok
    local req; req="$(srv_request "$DIR" 1)"
    assert_contains "$req" "X-Probe: alpha"
    assert_contains "$req" "X-Other: beta"
    _end
}

#[test]
it_still_sends_the_json_headers_of_the_json_helpers() {
    _want curl || return 0
    _begin 200
    http_post_json "http://127.0.0.1:$PORT/x" '{"k":1}' --header "X-Probe: alpha"
    local req; req="$(srv_request "$DIR" 1)"
    assert_contains "$req" "Content-Type: application/json"
    assert_contains "$req" "X-Probe: alpha"
    assert_contains "$req" '{"k":1}'
    _end
}

# -----------------------------------------------------------------------------
# --headers-from

#[test]
it_reads_header_lines_from_stdin_on_curl() {
    _want curl || return 0
    _begin 200
    http_get "http://127.0.0.1:$PORT/x" --headers-from - <<<$'Authorization: Bearer s3cret-token\nX-Second: two'
    assert_ok http_ok
    local req; req="$(srv_request "$DIR" 1)"
    assert_contains "$req" "Authorization: Bearer s3cret-token"
    assert_contains "$req" "X-Second: two"
    _end
}

#[test]
it_reads_header_lines_from_a_file_descriptor_on_curl() {
    _want curl || return 0
    _begin 200
    http_get "http://127.0.0.1:$PORT/x" --headers-from <(printf 'X-Fd: from a descriptor\n')
    assert_contains "$(srv_request "$DIR" 1)" "X-Fd: from a descriptor"
    _end
}

#[test]
it_sends_a_header_with_a_quote_and_a_backslash_intact_from_stdin() {
    _want curl || return 0
    _begin 200
    http_get "http://127.0.0.1:$PORT/x" --headers-from - <<<'X-Odd: say "hi" \ back'
    assert_contains "$(srv_request "$DIR" 1)" 'X-Odd: say "hi" \ back'
    _end
}

#[test]
it_keeps_a_stdin_header_off_the_command_line() {
    _want curl || return 0
    _begin slow:200:ok
    ( http_get "http://127.0.0.1:$PORT/x" --headers-from - <<<"Authorization: Bearer s3cret-token" ) &
    local bg=$!
    sleep 0.7
    local argv; argv="$(ps -eo args 2>/dev/null)"
    # the control: the running tool's command line is visible to this look
    assert_contains "$argv" "127.0.0.1:$PORT/x" "the look cannot see the tool's command line"
    assert_not_contains "$argv" "s3cret-token"
    wait "$bg"
    assert_contains "$(srv_request "$DIR" 1)" "Authorization: Bearer s3cret-token" "the header was never sent"
    _end
}

#[test]
it_puts_a_plain_header_option_on_the_command_line_as_the_control() {
    _want curl || return 0
    _begin slow:200:ok
    ( http_get "http://127.0.0.1:$PORT/x" --header "X-Plain: plain-token-123" ) &
    local bg=$!
    sleep 0.7
    assert_contains "$(ps -eo args 2>/dev/null)" "plain-token-123"
    wait "$bg"
    _end
}

#[test]
it_refuses_a_stdin_header_on_wget_with_status_2_and_says_why() {
    _want wget || return 0
    local out rc
    out="$(http_get "http://127.0.0.1:9/x" --headers-from - <<<"Authorization: Bearer s3cret-token" 2>&1)"; rc=$?
    assert_eq "$rc" "2"
    assert_contains "$out" "wget"
    assert_contains "$out" "command line"
    assert_not_contains "$out" "s3cret-token"
}

#[test]
it_uses_curl_for_a_stdin_header_when_the_module_sits_on_wget() {
    _want curl || return 0
    deps_has wget || { skip "wget is not on this machine"; return 0; }
    _begin 200
    _HTTP_IMPL=wget
    http_get "http://127.0.0.1:$PORT/x" --headers-from - <<<"Authorization: Bearer s3cret-token"
    assert_ok http_ok
    assert_contains "$(srv_request "$DIR" 1)" "Authorization: Bearer s3cret-token"
    _end
}

#[test]
it_refuses_header_lines_that_are_not_headers() {
    _want curl || return 0
    assert_exits 2 http_get "http://127.0.0.1:9/x" --headers-from - <<<"no colon here"
    assert_exits 2 http_get "http://127.0.0.1:9/x" --headers-from /nonexistent/headers
    assert_exits 2 http_get "http://127.0.0.1:9/x" --headers-from - </dev/null
    assert_exits 2 http_get "http://127.0.0.1:9/x" --header
}

# -----------------------------------------------------------------------------
# --body-file and --content-type

_body_file() { TMPF="$(mktemp)"; printf '%s' "$1" >"$TMPF"; }

#[test]
it_posts_a_body_from_a_file_with_its_content_type_on_curl() {
    _want curl || return 0
    _begin 200; _body_file $'a=1\nb=two words'
    http_post "http://127.0.0.1:$PORT/x" "" --body-file "$TMPF" --content-type text/plain
    assert_ok http_ok
    local req; req="$(srv_request "$DIR" 1)"
    assert_contains "$req" "POST /x"
    assert_contains "$req" "Content-Type: text/plain"
    assert_eq "${req#*$'\r\n\r\n'}" $'a=1\nb=two words'
    _end
}

#[test]
it_posts_a_body_from_a_file_with_its_content_type_on_wget() {
    _want wget || return 0
    _begin 200; _body_file $'a=1\nb=two words'
    http_post "http://127.0.0.1:$PORT/x" "" --body-file "$TMPF" --content-type text/plain
    assert_ok http_ok
    local req; req="$(srv_request "$DIR" 1)"
    assert_contains "$req" "POST /x"
    assert_contains "$req" "Content-Type: text/plain"
    assert_eq "${req#*$'\r\n\r\n'}" $'a=1\nb=two words'
    _end
}

#[test]
it_refuses_a_body_file_beside_inline_data_and_a_missing_file() {
    _want curl || return 0
    _body_file "x"
    assert_exits 2 http_post "http://127.0.0.1:9/x" "inline" --body-file "$TMPF"
    assert_exits 2 http_post "http://127.0.0.1:9/x" "" --body-file /nonexistent/body
    assert_exits 2 http_post "http://127.0.0.1:9/x" "" --content-type
    rm -f "$TMPF"
}

# -----------------------------------------------------------------------------
# --insecure

# _tls_server <port> <dir> -> a self-signed https server up, or skips
_tls_server() {
    deps_has openssl || { skip "openssl is not on this machine, so there is no self-signed host"; return 1; }
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
        -keyout "$2/k.pem" -out "$2/c.pem" -subj "/CN=127.0.0.1" -days 1 >/dev/null 2>&1 \
        || { skip "openssl could not make a certificate"; return 1; }
    openssl s_server -accept "$1" -cert "$2/c.pem" -key "$2/k.pem" -www >/dev/null 2>&1 &
    _SRV_PID=$!; _SRV_PORT="$1"
    sleep 0.7
}

#[test]
it_refuses_a_self_signed_host_unless_told_otherwise_on_curl() {
    _want curl || return 0
    PORT="$(srv_port)"; DIR="$(mktemp -d)"
    _tls_server "$PORT" "$DIR" || return 0
    assert_fails http_get "https://127.0.0.1:$PORT/"
    http_get "https://127.0.0.1:$PORT/" --insecure
    assert_ok http_ok
    _end
}

#[test]
it_refuses_a_self_signed_host_unless_told_otherwise_on_wget() {
    _want wget || return 0
    PORT="$(srv_port)"; DIR="$(mktemp -d)"
    _tls_server "$PORT" "$DIR" || return 0
    assert_fails http_get "https://127.0.0.1:$PORT/"
    http_get "https://127.0.0.1:$PORT/" --insecure
    assert_ok http_ok
    _end
}

#[test]
it_lets_a_download_skip_verification_on_one_call_only() {
    _want curl || return 0
    PORT="$(srv_port)"; DIR="$(mktemp -d)"; TMPF="$(mktemp)"
    _tls_server "$PORT" "$DIR" || return 0
    assert_ok http_download "https://127.0.0.1:$PORT/" "$TMPF" --insecure
    assert_fails http_download "https://127.0.0.1:$PORT/" "$TMPF"
    _end
}

# -----------------------------------------------------------------------------
# What the listing says

#[test]
it_lists_the_options_and_names_insecure_as_test_only() {
    local out; out="$(api_text "$ROOT_DIR" http)"
    assert_contains "$out" "--header"
    assert_contains "$out" "--headers-from"
    assert_contains "$out" "--body-file"
    assert_contains "$out" "--content-type"
    assert_contains "$out" "--insecure"
    assert_contains "$out" "test-only"
}

# -----------------------------------------------------------------------------
# Downloads and PUT, per tool

#[test]
it_sends_a_header_option_on_a_download_on_curl() {
    _want curl || return 0
    _begin 200:payload; TMPF="$(mktemp)"
    http_download "http://127.0.0.1:$PORT/f" "$TMPF" --header "X-Probe: alpha"
    assert_eq "$(cat "$TMPF")" "payload"
    assert_contains "$(srv_request "$DIR" 1)" "X-Probe: alpha"
    _end
}

#[test]
it_sends_a_header_option_on_a_download_on_wget() {
    _want wget || return 0
    _begin 200:payload; TMPF="$(mktemp)"
    http_download "http://127.0.0.1:$PORT/f" "$TMPF" --header "X-Probe: alpha"
    assert_eq "$(cat "$TMPF")" "payload"
    assert_contains "$(srv_request "$DIR" 1)" "X-Probe: alpha"
    _end
}

#[test]
it_puts_a_body_from_a_file_on_curl() {
    _want curl || return 0
    _begin 200; _body_file '{"name":"x"}'
    http_put "http://127.0.0.1:$PORT/r/1" --body-file "$TMPF" --content-type application/json
    local req; req="$(srv_request "$DIR" 1)"
    assert_contains "$req" "PUT /r/1"
    assert_contains "$req" "Content-Type: application/json"
    assert_eq "${req#*$'\r\n\r\n'}" '{"name":"x"}'
    _end
}

#[test]
it_puts_a_body_from_a_file_on_wget() {
    _want wget || return 0
    _begin 200; _body_file '{"name":"x"}'
    http_put "http://127.0.0.1:$PORT/r/1" --body-file "$TMPF" --content-type application/json
    local req; req="$(srv_request "$DIR" 1)"
    assert_contains "$req" "PUT /r/1"
    assert_contains "$req" "Content-Type: application/json"
    assert_eq "${req#*$'\r\n\r\n'}" '{"name":"x"}'
    _end
}

#[test]
it_reads_the_old_short_h_as_a_header_on_wget_where_wget_means_span_hosts() {
    _want wget || return 0
    _begin 200
    http_get "http://127.0.0.1:$PORT/x" -H "X-Probe: alpha"
    assert_ok http_ok
    assert_contains "$(srv_request "$DIR" 1)" "X-Probe: alpha"
    _end
}

#[test]
it_reads_the_old_short_h_as_a_header_on_curl() {
    _want curl || return 0
    _begin 200
    http_get "http://127.0.0.1:$PORT/x" -H "X-Probe: alpha"
    assert_contains "$(srv_request "$DIR" 1)" "X-Probe: alpha"
    _end
}

# -----------------------------------------------------------------------------
# A secret header under `set -x`: the trace goes to stderr, and into logs.

# _traced <fn> <args...> -> TRACE, what `set -x` printed for the call, and XT_AFTER
# set to on or off, whether the caller's tracing was still on when it returned
_traced() {
    local err; err="$(mktemp)"
    XT_AFTER="$( { set -x; "$@" >/dev/null; case $- in *x*) printf on ;; *) printf off ;; esac; } 2>"$err" )"
    TRACE="$(cat "$err")"
    rm -f "$err"
}

#[test]
it_keeps_a_stdin_header_out_of_the_trace_on_curl() {
    _want curl || return 0
    _begin 200
    _traced http_get "http://127.0.0.1:$PORT/x" --headers-from - <<<"Authorization: Bearer trace-secret-91"
    assert_contains "$TRACE" "http_get" "the trace shows nothing, so its absence proves nothing"
    assert_not_contains "$TRACE" "trace-secret-91"
    assert_contains "$(srv_request "$DIR" 1)" "Authorization: Bearer trace-secret-91" "the header was never sent"
    _end
}

#[test]
it_shows_a_plain_header_in_the_trace_as_the_control() {
    _want curl || return 0
    _begin 200
    _traced http_get "http://127.0.0.1:$PORT/x" --header "X-Plain: plain-trace-77"
    assert_contains "$TRACE" "plain-trace-77" "the trace cannot see header values at all"
    _end
}

#[test]
it_keeps_a_header_from_a_file_out_of_the_trace_on_curl() {
    _want curl || return 0
    _begin 200 200
    TMPF="$(mktemp)"; printf 'X-Token: file-secret-52\n' >"$TMPF"
    _traced http_get "http://127.0.0.1:$PORT/x" --headers-from "$TMPF"
    assert_not_contains "$TRACE" "file-secret-52"
    _traced http_post "http://127.0.0.1:$PORT/x" "a=1" --headers-from "$TMPF"
    assert_not_contains "$TRACE" "file-secret-52"
    _end
}

#[test]
it_keeps_a_header_out_of_the_trace_of_a_download_on_curl() {
    _want curl || return 0
    _begin 200
    TMPF="$(mktemp)"
    _traced http_download "http://127.0.0.1:$PORT/x" "$TMPF" --headers-from - <<<"Authorization: Bearer dl-secret-33"
    assert_contains "$TRACE" "http_download"
    assert_not_contains "$TRACE" "dl-secret-33"
    _end
}

#[test]
it_keeps_a_header_out_of_the_trace_when_wget_refuses_it() {
    _want wget || return 0
    _traced http_get "http://127.0.0.1:9/x" --headers-from - <<<"Authorization: Bearer refuse-secret-18"
    assert_contains "$TRACE" "http_get"
    assert_not_contains "$TRACE" "refuse-secret-18"
}

#[test]
it_keeps_a_malformed_header_line_out_of_the_trace() {
    _want curl || return 0
    _traced http_get "http://127.0.0.1:9/x" --headers-from - <<<"no colon secret-bad-line-64"
    assert_contains "$TRACE" "http_get"
    assert_not_contains "$TRACE" "secret-bad-line-64"
}

#[test]
it_leaves_the_callers_tracing_as_it_found_it() {
    _want curl || return 0
    _begin 200 200
    _traced http_get "http://127.0.0.1:$PORT/x" --headers-from - <<<"X-A: b"
    assert_eq "$XT_AFTER" "on" "tracing was on and the call turned it off for good"
    local out
    out="$( { http_get "http://127.0.0.1:$PORT/x" --headers-from - <<<"X-A: b" >/dev/null; case $- in *x*) printf on ;; *) printf off ;; esac; } 2>&1 )"
    assert_eq "$out" "off" "tracing was off and the call turned it on"
    _end
}
