#!/usr/bin/env bash
# A read costs about what the document weighs, not what it weighs squared.
#
# jq was asked to check every token of the document against JSON before reading
# it, with `gsub` and `scan` over the whole text, and that is quadratic: a read
# of a string out of a megabyte took three minutes. Each call here runs against
# a clock and is stopped by `timeout` where the clock fails it, so a regression
# goes red in seconds and not in minutes. The budget is a hundred times what a
# correct read takes on this machine; it is a bound and not a benchmark, and a
# number that feeds a decision comes from `benches/`.
#
# python and perl take the document as an argument, which the kernel caps at
# about 128 KB, so they run a document under it.

use json deps test

# The seconds a read of any size here may take
_JS_BUDGET=5

# _js_doc <kind> <bytes> -> a document of about that size on stdout
#   strings: an array of strings of a thousand characters
#   tokens:  an array of small objects, one token each of number, string, null
_js_doc() {
    local kind="$1" bytes="$2" n chunk
    case "$kind" in
        strings)
            chunk="$(printf 'abcdefghij%.0s' $(seq 1 100))"
            n=$(( bytes / 1004 ))
            printf '['
            printf '"%s",' $(seq 1 "$n" | sed "s/.*/$chunk/")
            printf '"last"]' ;;
        tokens)
            n=$(( bytes / 29 ))
            printf '['
            printf '{"n":1,"s":"ab\\"c","f":null},%.0s' $(seq 1 "$n")
            printf '{"n":2}]' ;;
    esac
}

# _js_timed <backend> <document> <path> -> `text|status|seconds`, killed at the budget
_js_timed() {
    local backend="$1" doc="$2" path="$3" out rc=0 t0 t1 f
    t0="$EPOCHREALTIME"
    # The document goes through a file: it is more than an argument can hold.
    f="$(mktemp)"; printf '%s' "$doc" > "$f"
    out="$(timeout "$_JS_BUDGET" bash -c '
        . "$1/init" || exit 1
        use json
        json_detect; _JSON_IMPL="$2"
        json_get "$(cat "$3")" "$4"' _ "$NUTSHELL_ROOT" "$backend" "$f" "$path" 2>/dev/null)" || rc=$?
    rm -f "$f"
    t1="$EPOCHREALTIME"
    printf '%s|%s|%s' "$out" "$rc" "$(( (${t1/./} - ${t0/./}) / 1000000 ))"
}

#[test]
it_reads_a_string_out_of_a_megabyte_under_jq_inside_the_budget() {
    deps_has jq || { skip "no jq on this machine"; return 0; }
    local doc got; doc="$(_js_doc strings 1000000)"
    assert_eq "$(( ${#doc} > 900000 ))" "1" "the document is a megabyte"
    got="$(_js_timed jq "$doc" 10)"
    assert_eq "${got%|*|*}" "abcdefghij$(printf 'abcdefghij%.0s' $(seq 1 99))" "jq, a string out of a megabyte"
    assert_eq "$(( ${got##*|} < _JS_BUDGET ))" "1" "jq took ${got##*|} s of $_JS_BUDGET"
}

#[test]
it_reads_an_integer_out_of_a_megabyte_of_small_tokens_under_jq_inside_the_budget() {
    deps_has jq || { skip "no jq on this machine"; return 0; }
    local doc got; doc="$(_js_doc tokens 900000)"
    got="$(_js_timed jq "$doc" 5.n)"
    assert_eq "${got%|*|*}" "1" "jq, an integer out of small tokens"
    assert_eq "$(( ${got##*|} < _JS_BUDGET ))" "1" "jq took ${got##*|} s of $_JS_BUDGET"
}

#[test]
it_reads_an_integer_out_of_a_hundred_kilobytes_under_python_and_perl_inside_the_budget() {
    local doc got b ran=0; doc="$(_js_doc tokens 100000)"
    for b in python perl; do
        case "$b" in
            python) { deps_has python3 || deps_has python; } || continue ;;
            perl) deps_has perl || continue ;;
        esac
        ran=1
        got="$(_js_timed "$b" "$doc" 5.n)"
        assert_eq "${got%|*|*}" "1" "$b, an integer out of 100 KB"
        assert_eq "$(( ${got##*|} < _JS_BUDGET ))" "1" "$b took ${got##*|} s of $_JS_BUDGET"
    done
    [ "$ran" = 1 ] || skip "no python or perl on this machine"
}
