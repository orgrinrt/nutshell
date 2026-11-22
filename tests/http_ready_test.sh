#!/usr/bin/env bash
# Tests for what http says about the tools it needs.
#
# It runs on curl or wget and on nothing else: HTTPS from perl needs modules no
# base image carries, so there is no third rung, and a machine with neither says
# which two it wanted rather than failing later in a request.

use http deps test
source "${BASH_SOURCE[0]%/*}/fixtures/hide_tools.sh"

#[test]
it_names_both_missing_tools_when_it_has_neither() {
    _hide_tools curl wget
    http_detect
    local out rc
    out="$(http_ready 2>&1)"; rc=$?
    assert_eq "$rc" "1"
    assert_contains "$out" "curl"
    assert_contains "$out" "wget"
    assert_eq "$(http_impl)" ""
}

#[test]
it_is_ready_and_silent_with_curl() {
    deps_has curl || { test_skip "curl is not on this machine"; return 0; }
    local out
    out="$(http_ready 2>&1)"
    assert_ok http_ready
    assert_eq "$out" ""
    assert_eq "$(http_impl)" "curl"
}

#[test]
it_falls_to_wget_when_curl_is_gone() {
    deps_has wget || { test_skip "wget is not on this machine"; return 0; }
    _hide_tools curl
    http_detect
    assert_ok http_ready
    assert_eq "$(http_impl)" "wget"
}

#[test]
it_never_falls_to_perl() {
    _hide_tools curl wget
    http_detect
    assert_fails http_ready
    assert_eq "$(http_impl)" ""
}

#[test]
it_refuses_a_request_without_a_tool_and_says_why() {
    _hide_tools curl wget
    http_detect
    assert_fails http_get "http://127.0.0.1:9/"
    assert_contains "$(http_body)" "curl"
}
