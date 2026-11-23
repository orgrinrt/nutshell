#!/usr/bin/env bash
# One contract for the reads, held against every backend this machine has.
#
# `json_get`, `json_has`, `json_keys`, `json_type`, `json_length` and
# `json_valid` are documented to give one text and one status whoever reads, and
# three backends and a reader in bash each made their own answers for the same
# call: a digit key on an object was an error under jq, a document with text
# after it gave a value and jq's own status 5, a float was spelled four ways,
# `a.-1` was the last element under python, and the length of a number was a
# number, 1, or nothing. Every row below is a call, the status it gives and the
# text it prints, written out here and not taken from any backend, and each
# runs under:
#
#   - each backend named outright, `_JSON_IMPL`, which skips the reader in bash
#     that answers first for a small document, and
#   - each backend picked as `deps` does, with the others hidden, which has that
#     reader in front of it.
#
# The contract, from the module header and the reader in bash where the header
# is silent:
#
#   - status 0 found, 1 not there or not JSON; a document is exactly one value,
#     so text after it, a second value and nothing at all are not JSON, and
#     neither is a literal JSON does not have (`01`, `.5`, `1.`, `+1`, `NaN`)
#   - a segment of digits indexes an array and is a plain key on an object; any
#     other segment on an array is not there, so no `-1`, no `+1`, no `1e0`
#   - a number prints as the document wrote it, alone or inside a container
#   - the length of an array or object is its count, of a string its
#     characters, of null 0, and a number or a boolean has none
#   - an empty segment is dropped, so a path of nothing but those is the whole
#     document and an empty key cannot be reached
#
# Not in the contract, because the backends cannot be made to agree on it: a
# string that holds a NUL or a lone surrogate, which jq and perl refuse or
# repair and python and the reader in bash keep.

use json deps test
source "${BASH_SOURCE[0]%/*}/fixtures/hide_tools.sh"

# One row a line: op ~ document ~ path ~ status ~ text, a newline in the text
# written `\n`. The document and the path are the call's arguments.
_JC_CASES=$(cat <<'CASES'
get~{"a":{"0":"z"}}~a.0~0~z
get~{"a":{"0":"z","1":"w"}}~a.1~0~w
get~{"a":[{"0":"z"}]}~a.0.0~0~z
get~{"1":"x"}~1~0~x
get~{"a":[1,2]}~a.1~0~2
get~{"a":[1,2]}~a.01~0~2
get~{"a":[1,2]}~a.5~1~
get~{"a":[1,2]}~a.-1~1~
get~{"a":[1,2]}~a.+1~1~
get~{"a":[1,2]}~a.1e0~1~
get~[1,2,3]~x~1~
get~{"a":"x"} trailing~a~1~
get~[1,2]garbage~0~1~
get~{"a":1}{"b":2}~a~1~
get~not json~a~1~
get~{"a":}~a~1~
get~{"a":01}~a~1~
get~{"a":.5}~a~1~
get~{"a":1.}~a~1~
get~{"a":+1}~a~1~
get~{"a":NaN}~a~1~
get~{"a":Infinity}~a~1~
get~  {"a":1}  ~a~0~1
get~{"a":1e3}~a~0~1e3
get~{"a":1E5}~a~0~1E5
get~{"a":1.0}~a~0~1.0
get~{"a":1.50}~a~0~1.50
get~{"a":0.10}~a~0~0.10
get~{"a":1e-5}~a~0~1e-5
get~{"a":-1.0e+2}~a~0~-1.0e+2
get~{"a":-0}~a~0~-0
get~{"a":1e999}~a~0~1e999
get~{"a":12345678901234567890}~a~0~12345678901234567890
get~{"a":[1e3,2.50]}~a~0~[1e3,2.50]
get~{"a":[1e999]}~a~0~[1e999]
get~{"b":[1.0],"a":2e2}~~0~{"a":2e2,"b":[1.0]}
get~{"a":{"b":[1,{"c":2}]}}~a.b.1.c~0~2
get~{"a":null}~a~0~null
get~{"a":true}~a~0~true
get~{"a":"x"}~a.b~1~
get~{"a":"x"}~a.0~1~
get~{"a":[1]}~a.b~1~
get~{"a":"é😀"}~a~0~é😀
get~{"é":1}~é~0~1
get~{"a":"x\ny"}~a~0~x\ny
get~{"b":1,"a":2,"é":3,"Z":4}~~0~{"Z":4,"a":2,"b":1,"é":3}
get~{"a":{"":5}}~a.""~0~{"":5}
get~{"":5}~""~0~{"":5}
get~{"a":1}~a..~0~1
length~3~~1~
length~true~~1~
length~{"a":true}~a~1~
length~{"a":false}~a~1~
length~{"a":1.5}~a~1~
length~{"a":-3}~a~1~
length~1e3~~1~
length~null~~0~0
length~"abc"~~0~3
length~"é"~~0~1
length~{"a":""}~a~0~0
length~[1,2]~~0~2
length~[]~~0~0
length~{"a":1}~~0~1
length~{"a":[1,2,3]}~a~0~3
length~{"a":[1,[2,3]]}~a.1~0~2
length~{"a":{"0":1}}~a.0~1~
length~[1,2] x~~1~
type~{"a":{"0":1}}~a.0~0~number
type~{"a":"1"}~a~0~string
type~{"a":1.0}~a~0~number
type~{"a":1e3}~a~0~number
type~{"a":[1]}~a.1~1~
type~{"a":[1]}~a.0~0~number
type~true~~0~boolean
type~null~~0~null
type~[]~~0~array
type~1 2~~1~
type~{"a":1} x~~1~
type~nul~~1~
keys~{"b":1,"a":2}~~0~a\nb
keys~{"é":1,"z":2,"A":3}~~0~A\nz\né
keys~[5,6]~~0~0\n1
keys~{"a":{"0":1}}~a~0~0
keys~{}~~0~
keys~3~~1~
keys~null~~1~
keys~"s"~~1~
keys~{"a":1} x~~1~
has~{"a":{"0":1}}~a.0~0~
has~{"a":[0]}~a.0~0~
has~{"a":[0]}~a.1~1~
has~{"a":1}~b~1~
has~{"a":null}~a~1~
has~{"a":""}~a~1~
has~{"a":1} x~a~1~
valid~{"a":1}~~0~
valid~ {"a":1} ~~0~
valid~null~~0~
valid~"s"~~0~
valid~[1,[2,[3]]]~~0~
valid~{"a":1e999}~~0~
valid~{"a":1} x~~1~
valid~1 2~~1~
valid~{"a":1}{"b":2}~~1~
valid~nul~~1~
valid~{"a":}~~1~
valid~[1,2,]~~1~
valid~{'a':1}~~1~
valid~01~~1~
valid~.5~~1~
valid~1.~~1~
valid~+1~~1~
valid~NaN~~1~
valid~Infinity~~1~
CASES
)

# _jc_backends -> the backends this machine can run, one per line; the reader in
# bash is always one
_jc_backends() {
    deps_has jq && printf 'jq\n'
    { deps_has python3 || deps_has python; } && printf 'python\n'
    deps_has perl && printf 'perl\n'
    printf 'bash\n'
}

# _jc_others <backend> -> the tools to hide so that deps picks that backend
_jc_others() {
    case "$1" in
        jq)     printf '%s ' python python3 perl ;;
        python) printf '%s ' jq gojq jaq perl ;;
        perl)   printf '%s ' jq gojq jaq python python3 ;;
        bash)   printf '%s ' jq gojq jaq python python3 perl ;;
    esac
}

# _jc_call <op> <document> <path> -> `text|status` of the call, the text on one
# line with a newline written `\n`
_jc_call() {
    local out rc=0
    out="$(json_"$1" "$2" "$3" 2>/dev/null)" || rc=$?
    out="${out//$'\n'/\\n}"
    printf '%s|%s' "$out" "$rc"
}

# _jc_rows <mode> <backend> -> one `op|document|path -> got` line per case, the
# call made under the backend named outright or picked from what deps finds
_jc_rows() {
    local mode="$1" backend="$2" op doc path rc want
    (
        if [ "$mode" = picked ]; then
            # shellcheck disable=SC2046
            _hide_tools $(_jc_others "$backend")
            json_detect
        else
            json_detect
            _JSON_IMPL="$backend"
        fi
        while IFS='~' read -r op doc path rc want; do
            printf '%s\t%s\t%s\t%s\n' "$op" "$doc" "$path" "$(_jc_call "$op" "$doc" "$path")"
        done <<<"$_JC_CASES"
    )
}

# _jc_check <mode> <backend> -> every case answers its row, text and status
_jc_check() {
    local mode="$1" backend="$2" op doc path rc want got report=""
    local -a rows=()
    mapfile -t rows < <(_jc_rows "$mode" "$backend")
    local i=0
    while IFS='~' read -r op doc path rc want; do
        got="${rows[i]#*$'\t'*$'\t'*$'\t'}"
        i=$((i + 1))
        [ "$got" = "${want}|${rc}" ] && continue
        report+="json_${op} [${doc}] [${path}] under ${backend} (${mode}): expected [${want}|${rc}], got [${got}]"$'\n'
    done <<<"$_JC_CASES"
    assert_empty "$report" "rows that answer otherwise than written"
}

#[test]
it_has_the_reader_in_bash_and_at_least_one_tool_to_compare_it_with() {
    # The control for the matrix: with only the reader in bash there is nothing
    # to agree with, and the rows below would all pass for one backend.
    local n; n="$(_jc_backends | wc -l | tr -d ' ')"
    if [ "$n" -lt 2 ]; then skip "no jq, python or perl on this machine"; return 0; fi
    assert_ok test "$n" -ge 2
}

#[test]
it_holds_the_cases_under_the_reader_in_bash_alone() {
    _jc_check named bash
}

#[test]
it_holds_the_cases_with_every_tool_hidden() {
    _jc_check picked bash
}

#[test]
it_holds_the_cases_under_jq_named_outright() {
    deps_has jq || { skip "no jq on this machine"; return 0; }
    _jc_check named jq
}

#[test]
it_holds_the_cases_under_jq_picked_by_deps() {
    deps_has jq || { skip "no jq on this machine"; return 0; }
    _jc_check picked jq
}

#[test]
it_holds_the_cases_under_python_named_outright() {
    { deps_has python3 || deps_has python; } || { skip "no python on this machine"; return 0; }
    _jc_check named python
}

#[test]
it_holds_the_cases_under_python_picked_by_deps() {
    { deps_has python3 || deps_has python; } || { skip "no python on this machine"; return 0; }
    _jc_check picked python
}

#[test]
it_holds_the_cases_under_perl_named_outright() {
    deps_has perl || { skip "no perl on this machine"; return 0; }
    _jc_check named perl
}

#[test]
it_holds_the_cases_under_perl_picked_by_deps() {
    deps_has perl || { skip "no perl on this machine"; return 0; }
    _jc_check picked perl
}

#[test]
it_refuses_a_row_a_backend_gets_wrong() {
    # The control for `_jc_check`: a row whose expected text is off by one
    # character has to fail, or a green matrix says nothing.
    local saved="$_JC_CASES"
    _JC_CASES='get~{"a":1e3}~a~0~1000'
    assert_refused _jc_check named bash
    _JC_CASES='get~{"a":1e3}~a~1~1e3'
    assert_refused _jc_check named bash
    _JC_CASES="$saved"
}
