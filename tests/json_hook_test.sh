#!/usr/bin/env bash
# Tests for the reads a hook makes: one plain path out of a small payload.
#
# A per-tool-call hook reads its payload and takes a field or two out of it,
# every call. Where the document is small and the path is plain, the reader in
# bash answers without running jq, and its answer has to be the one jq gives,
# byte for byte. Where it could differ (a number jq spells another way, a
# string jq would repair, a document past the size where jq is the faster) the
# question goes to the tool. The expected values are what jq 1.7 printed for
# the same calls, written in.

use json deps test
source "${BASH_SOURCE[0]%/*}/fixtures/hide_tools.sh"

# A payload of the shape a hook gets: strings with escapes, a non-ASCII
# description, numbers, a boolean, a nested object and an array.
_JH_DOC='{"session_id":"0f8e6a52","transcript_path":"/h/s/.claude/p.jsonl","cwd":"/h/s/work","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cd /w && grep -rn \"needle\" src | head","description":"Search — the “sources”","timeout":120000,"run_in_background":false},"tool_response":{"stdout":"a\tb\nc","exit":0,"tags":["x","y",null,true,-3]},"k.d":{"z":1},"e":{},"u":"é😀 \u001f"}'

# _jh_spy -> a jq first on PATH that notes each run in `$_JH_LOG` and then runs
# the real one; deps made to look again. Skips where there is no jq.
_jh_spy() {
    deps_has jq || { skip "jq is not on this machine"; return 1; }
    local real; real="$(deps_path jq)"
    _JH_DIR="$(mktemp -d)"; _JH_LOG="$_JH_DIR/log"; : > "$_JH_LOG"
    mkdir -p "$_JH_DIR/bin"
    printf '#!/bin/sh\necho run >> "%s"\nexec "%s" "$@"\n' "$_JH_LOG" "$real" > "$_JH_DIR/bin/jq"
    chmod +x "$_JH_DIR/bin/jq"
    PATH="$_JH_DIR/bin:$PATH"
    deps_forget
    json_detect
}

# _jh_runs -> how many times jq ran since the spy was set
_jh_runs() { local n=0 l; while IFS= read -r l; do n=$((n + 1)); done < "$_JH_LOG"; printf '%s' "$n"; }

# _jh_cases -> path, then the text jq prints for `json_get` of it, a pair a line
# apart; a tab in the answer is written as one
_jh_check_gets() {
    local why="$1"
    assert_eq "$(json_get "$_JH_DOC" tool_name)" "Bash" "$why"
    assert_eq "$(json_get "$_JH_DOC" tool_input.command)" 'cd /w && grep -rn "needle" src | head' "$why"
    assert_eq "$(json_get "$_JH_DOC" tool_input.description)" 'Search — the “sources”' "$why"
    assert_eq "$(json_get "$_JH_DOC" tool_input.timeout)" "120000" "$why"
    assert_eq "$(json_get "$_JH_DOC" tool_input.run_in_background)" "false" "$why"
    assert_eq "$(json_get "$_JH_DOC" tool_input)" '{"command":"cd /w && grep -rn \"needle\" src | head","description":"Search — the “sources”","run_in_background":false,"timeout":120000}' "$why"
    assert_eq "$(json_get "$_JH_DOC" tool_response)" '{"exit":0,"stdout":"a\tb\nc","tags":["x","y",null,true,-3]}' "$why"
    assert_eq "$(json_get "$_JH_DOC" tool_response.stdout)" "a	b
c" "$why"
    assert_eq "$(json_get "$_JH_DOC" tool_response.tags)" '["x","y",null,true,-3]' "$why"
    assert_eq "$(json_get "$_JH_DOC" tool_response.tags.2)" "null" "$why"
    assert_eq "$(json_get "$_JH_DOC" '"k.d".z')" "1" "$why"
    assert_eq "$(json_get "$_JH_DOC" e)" "{}" "$why"
    assert_eq "$(json_get "$_JH_DOC" u)" "é😀 $(printf '\037')" "$why"
    assert_eq "$(json_keys "$_JH_DOC" | tr '\n' ' ')" "cwd e hook_event_name k.d session_id tool_input tool_name tool_response transcript_path u " "$why"
    assert_eq "$(json_keys "$_JH_DOC" tool_input | tr '\n' ' ')" "command description run_in_background timeout " "$why"
    assert_eq "$(json_length "$_JH_DOC" tool_input)" "4" "$why"
    assert_eq "$(json_length "$_JH_DOC" tool_input.description)" "22" "$why"
    assert_eq "$(json_length "$_JH_DOC" u)" "4" "$why"
    assert_eq "$(json_type "$_JH_DOC" tool_input.timeout)" "number" "$why"
    assert_eq "$(json_type "$_JH_DOC" tool_response.tags)" "array" "$why"
    assert_ok json_has "$_JH_DOC" tool_input.command
    assert_fails json_has "$_JH_DOC" tool_input.nope
    assert_fails json_has "$_JH_DOC" tool_response.tags.2
}

#[test]
it_answers_a_plain_path_of_a_small_payload_without_running_jq() {
    _jh_spy || return 0
    _jh_check_gets "the floor, jq present"
    assert_eq "$(_jh_runs)" "0" "jq ran for a plain path of a small payload"
    rm -rf "$_JH_DIR"
}

#[test]
it_gives_what_jq_gives_for_the_payload_when_jq_is_asked_outright() {
    # The control: the same calls through jq itself print the same text, so the
    # literals above are jq's and not the floor's.
    _jh_spy || return 0
    _JSON_IMPL=jq
    _jh_check_gets "through jq"
    assert_ne "$(_jh_runs)" "0"
    rm -rf "$_JH_DIR"
}

#[test]
it_gives_the_same_with_no_tool_at_all() {
    _hide_tools jq gojq jaq python python3 perl
    json_detect
    _jh_check_gets "no tool"
}

#[test]
it_asks_jq_where_it_would_spell_a_number_another_way() {
    # jq 1.7 prints an exponent as `1E+3`, and the floor prints numbers as
    # written; and `length` of a number is its absolute value to jq.
    _jh_spy || return 0
    assert_eq "$(json_get '{"a":1e3}' a)" "1E+3"
    assert_eq "$(json_get '{"a":[1e3,2]}' a)" "[1E+3,2]"
    assert_eq "$(json_length '{"a":-5}' a)" "5"
    assert_ne "$(_jh_runs)" "0"
    rm -rf "$_JH_DIR"
}

#[test]
it_asks_jq_where_the_string_is_not_one_it_would_print_as_written() {
    # A byte that is not UTF-8 jq replaces with U+FFFD; a lone surrogate it
    # refuses; an escaped NUL it keeps, where bash cannot hold one.
    _jh_spy || return 0
    assert_eq "$(json_get "$(printf '{"a":"x\377y"}')" a)" "x�y"
    json_get '{"a":"\ud800x"}' a >/dev/null 2>&1; assert_eq "$?" "1" "a lone surrogate is not JSON to jq"
    assert_eq "$(json_get '{"a":{"b":"\u0000c"}}' a)" '{"b":"\u0000c"}'
    assert_ne "$(_jh_runs)" "0"
    rm -rf "$_JH_DIR"
}

#[test]
it_asks_jq_for_a_number_segment_on_an_object() {
    # jq reads a segment of digits as an index, and an object has none.
    _jh_spy || return 0
    json_get '{"1":"x"}' 1 >/dev/null 2>&1; assert_ne "$?" "0"
    assert_eq "$(json_get '{"1":"x"}' 1 2>/dev/null)" ""
    rm -rf "$_JH_DIR"
}

#[test]
it_hands_a_document_past_the_floor_limit_to_jq() {
    _jh_spy || return 0
    local pad doc
    pad="$(printf '%*s' "$(( _JSON_FLOOR_MAX + 1 ))" '' | tr ' ' x)"
    doc="{\"a\":\"${pad}\",\"b\":7}"
    assert_eq "$(json_get "$doc" b)" "7"
    assert_ne "$(_jh_runs)" "0"
    : > "$_JH_LOG"
    doc='{"a":"x","b":7}'
    assert_eq "$(json_get "$doc" b)" "7"
    assert_eq "$(_jh_runs)" "0"
    rm -rf "$_JH_DIR"
}

#[test]
it_says_absent_for_has_where_get_prints_null_or_nothing() {
    # What `json_has` meant through a capture of `json_get`: present and not
    # printing empty or `null`.
    assert_fails json_has '{"a":null}' a
    assert_fails json_has '{"a":""}' a
    assert_fails json_has '{"a":"null"}' a
    assert_fails json_has '{"a":"\n\n"}' a
    assert_ok json_has '{"a":"\nx"}' a
    assert_ok json_has '{"a":false}' a
    assert_ok json_has '{"a":0}' a
    assert_ok json_has '{"a":[]}' a
}

#[test]
it_loads_no_tool_backend_writer_or_deps_for_a_read() {
    # In a bash of its own, so nothing this process loaded is there.
    local out
    out="$(env -i HOME="$HOME" PATH="$PATH" bash -c '
        . "$1/init" || exit 1
        use json
        json_get "{\"a\":{\"b\":2}}" a.b
        for f in deps_has _json_get_jq _json_get_python _json_get_perl _json_set_jq _json_q_help _json_query_run _json_object_build; do
            declare -F "$f" >/dev/null && printf "loaded:%s\n" "$f"
        done
        json_set "{}" a 1 || printf "no tool\n"
        declare -F deps_has >/dev/null && printf "deps after a write\n"
        json_object k v
    ' _ "$NUTSHELL_ROOT" 2>&1)"
    assert_eq "$(printf '%s\n' "$out" | head -1)" "2"
    assert_not_contains "$out" "loaded:"
    assert_contains "$out" "deps after a write"
    assert_contains "$out" '{"k":"v"}'
}

#[test]
it_hands_a_document_of_more_values_than_the_floor_budget_to_jq() {
    _jh_spy || return 0
    local i doc="[" n=$(( _JSON_FLOOR_NODES + 1 ))
    for (( i = 0; i < n; i++ )); do doc+="$i,"; done
    doc+="7]"
    assert_eq "$(json_get "$doc" "$n")" "7"
    assert_ne "$(_jh_runs)" "0"
    : > "$_JH_LOG"
    doc='[1,2,7]'
    assert_eq "$(json_get "$doc" 2)" "7"
    assert_eq "$(_jh_runs)" "0"
    rm -rf "$_JH_DIR"
}
