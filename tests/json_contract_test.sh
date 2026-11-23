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

# --- which backend answers ----------------------------------------------------
#
# The rows above agree whoever answers, which also hides a backend that hands
# every number to the reader in bash: the text is right and the work is a whole
# parse in bash. So here the reader is replaced by one that notes each call, and
# a row says whether it was asked.

# _jc_asks <backend> <document> <path> -> `text|status|asked`, asked being 1 where
# the call went to the reader in bash and 0 where the backend answered
_jc_asks() {
    local f out rc=0
    f="$(mktemp)"
    out="$(
        eval "$(declare -f _json_get_bash | sed '1s/^_json_get_bash/_jc_real_reader/')"
        _json_get_bash() { echo asked >> "$f"; _jc_real_reader "$@"; }
        json_detect
        _JSON_IMPL="$1"
        json_get "$2" "$3" 2>/dev/null
    )" || rc=$?
    out="${out//$'\n'/\\n}"
    printf '%s|%s|%s' "$out" "$rc" "$([ -s "$f" ] && echo 1 || echo 0)"
    rm -f "$f"
}

# One row a line: document ~ path ~ text ~ asked by jq ~ asked by python ~ asked
# by perl. A number that is a fraction, an exponent or `-0` is spelled by the
# reader in bash under jq and perl, which respell it; python keeps the text of
# a number as the document gave it and asks nobody. Everything else is the
# backend's own.
_JC_ASKS=$(cat <<'CASES'
{"a":7}~a~7~0~0~0
{"a":12345678901234567}~a~12345678901234567~1~0~0
{"a":"v1.2"}~a~v1.2~0~0~0
{"a":["v1.2",3],"b":1.5}~a~["v1.2",3]~0~0~0
{"a":{"b":[1,2,{"c":0}]}}~a~{"b":[1,2,{"c":0}]}~0~0~0
{"a":1.5}~a~1.5~1~0~1
{"a":1e3}~a~1e3~1~0~1
{"a":-0}~a~-0~0~0~1
{"a":[1,{"b":2.5}]}~a~[1,{"b":2.5}]~1~0~1
CASES
)

_jc_check_asks() {
    local backend="$1" col="$2" doc path want ask_jq ask_py ask_pl got expect report=""
    while IFS='~' read -r doc path want ask_jq ask_py ask_pl; do
        case "$col" in jq) expect="$ask_jq" ;; python) expect="$ask_py" ;; perl) expect="$ask_pl" ;; esac
        got="$(_jc_asks "$backend" "$doc" "$path")"
        [ "$got" = "${want}|0|${expect}" ] && continue
        report+="json_get [${doc}] [${path}] under ${backend}: expected [${want}|0|${expect}], got [${got}]"$'\n'
    done <<<"$_JC_ASKS"
    assert_empty "$report" "calls answered by the wrong reader or with the wrong text"
}

#[test]
it_answers_what_jq_can_spell_itself_without_the_reader_in_bash() {
    deps_has jq || { skip "no jq on this machine"; return 0; }
    _jc_check_asks jq jq
}

#[test]
it_answers_every_number_python_reads_without_the_reader_in_bash() {
    { deps_has python3 || deps_has python; } || { skip "no python on this machine"; return 0; }
    _jc_check_asks python python
}

#[test]
it_answers_what_perl_can_spell_itself_without_the_reader_in_bash() {
    deps_has perl || { skip "no perl on this machine"; return 0; }
    _jc_check_asks perl perl
}

# --- where the reader in bash cannot answer ------------------------------------
#
# A shell without it, and a document nested deeper than it holds, get the
# backend's own spelling of a number it would respell, and a status of 0, in
# place of nothing. That text is the one place a backend differs, so it is
# written out per backend here and the header names it.

# _jc_without_reader <backend> <document> <path> -> `text|status` with the reader
# in bash gone
_jc_without_reader() {
    local out rc=0
    out="$(
        unset -f _json_get_bash
        json_detect
        _JSON_IMPL="$1"
        json_get "$2" "$3" 2>/dev/null
    )" || rc=$?
    printf '%s|%s' "$out" "$rc"
}

#[test]
it_spells_a_number_its_own_way_where_there_is_no_reader_in_bash_under_jq() {
    deps_has jq || { skip "no jq on this machine"; return 0; }
    assert_eq "$(_jc_without_reader jq '{"a":1e3}' a)" "1E+3|0"
    assert_eq "$(_jc_without_reader jq '{"a":7}' a)" "7|0"
    assert_eq "$(_jc_without_reader jq '{"a":[1e3,2]}' a)" "[1E+3,2]|0"
}

#[test]
it_spells_a_number_its_own_way_where_there_is_no_reader_in_bash_under_perl() {
    deps_has perl || { skip "no perl on this machine"; return 0; }
    assert_eq "$(_jc_without_reader perl '{"a":1e3}' a)" "1000|0"
    assert_eq "$(_jc_without_reader perl '{"a":7}' a)" "7|0"
}

#[test]
it_keeps_the_text_of_a_number_under_python_with_no_reader_in_bash() {
    { deps_has python3 || deps_has python; } || { skip "no python on this machine"; return 0; }
    assert_eq "$(_jc_without_reader python '{"a":1e3}' a)" "1e3|0"
    assert_eq "$(_jc_without_reader python '{"a":[1.50,-0]}' a)" "[1.50,-0]|0"
}

# A document nested past what the reader in bash holds, with a number the tool
# would respell: the tool's text, not nothing.
_jc_deep() {
    local open="" close="" i
    for (( i = 0; i < 450; i++ )); do open+="["; close+="]"; done
    printf '{"a":%s,"d":%s%s}' "$1" "$open" "$close"
}

#[test]
it_answers_a_respelled_number_of_a_document_the_reader_in_bash_cannot_hold() {
    local doc b want
    doc="$(_jc_deep 1.5)"
    # Not jq, which refuses a document nested past 256 before the reader in bash
    # could have been asked.
    for b in python perl; do
        case "$b" in
            python) { deps_has python3 || deps_has python; } || continue ;;
            perl) deps_has perl || continue ;;
        esac
        want="$(_jc_without_reader "$b" "$doc" a)"
        assert_eq "$want" "1.5|0" "$b with no reader in bash"
        assert_eq "$(_jc_call_under "$b" get "$doc" a)" "1.5|0" "$b past the reader's depth"
    done
}

# _jc_call_under <backend> <op> <document> <path> -> `text|status`, the backend named outright
_jc_call_under() {
    local out rc=0
    out="$(json_detect; _JSON_IMPL="$1"; json_"$2" "$3" "$4" 2>/dev/null)" || rc=$?
    printf '%s|%s' "$out" "$rc"
}
