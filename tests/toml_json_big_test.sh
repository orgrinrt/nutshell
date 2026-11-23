#!/usr/bin/env bash
# Tests for `toml_to_json` on a file large enough that how it is read matters.
#
# The workspace's task tracker converts about 4 MB of TOML per run, and the
# conversion cost about 1.2 s per MB, so a large file has a path of its own: the
# JSON kept for the next process that reads the same text, and taplo's JSON
# taken as it is, where taplo is present and the file holds nothing it would
# rewrite. A small file keeps the path it had, through the tree.
#
# Each process is a fresh bash under `env -i` with a cache directory of its own,
# so nothing the test process holds reaches it. A reader is picked by hiding the
# others from `deps`, and taplo is reached through a proxy that logs every call
# and runs the real one, so the route a file took is read from the log and not
# guessed from the answer. The expected JSON of the parity case is taplo's output
# put through jq, which is not the code under test.

use test deps

INIT="${BASH_SOURCE[0]%/*}/../init"

# _tbg_file <path> [extra lines] -> a tracker-shaped file of about 80 KB, past
# the size at which a file takes the large path, every note written as one basic
# string with escapes, and every seventh entry a multi-line one
_tbg_file() {
    local f="$1" extra="${2:-}" i body
    body='a note with \"quotes\", a back\\slash, a tab\there,\nand a second line,\n\nand a third, a control \u0001 and \u001f, an é and a smiley \U0001F600.'
    # What the compaction of taplo's JSON could confuse for structure: a key and
    # a string that start with a colon and a space, a quote and a colon inside a
    # key, a signed zero, nested and empty arrays and tables.
    cat > "$f" <<'EOT'
zero = -0
": colon-first" = 1
"a\": b" = 2
lead = ": starts with colon space"
says = "x\": y"
mixed = ["a", ": d", "e\": f", 1, true]
nested = [[1, 2], [3, [4, 5]], []]
empty = []
inline = { a = 1, b = { c = "d: e" }, ": f" = 2, e = {} }
dotted.a.b = 1
ml = """
first
second \
   third"""
EOT
    for (( i = 0; i < 150; i++ )); do
        printf '[[action]]\nkey = "ticket_%d"\nowner = "op"\nnote = "%d: %s %s %s"\n' \
            "$i" "$i" "$body" "$body" "$body" >> "$f"
        (( i % 7 )) || printf 'detail = """\nentry %d, over lines\nwith a "quote" and a fold \\\n   into one.\n"""\n' "$i" >> "$f"
        printf 'n = %d\nok = true\n\n' "$i" >> "$f"
    done
    printf '%s' "$extra" >> "$f"
}

# _tbg_run <hidden tools> <cache dir> <prelude> <file> [path prefix] -> what
# `toml_to_json` printed, and stderr, in a new process; the code in `_tbg_rc`
_tbg_run() {
    local out
    out="$(env -i HOME="$HOME" PATH="${5:+$5:}$PATH" XDG_CACHE_HOME="$2" NUT_DEPS_HIDE="$1" \
        bash -c '. "$1" || exit 1; use toml::json; eval "$3"; toml_to_json "$2"' _ "$INIT" "$4" "$3" 2>&1)"
    _tbg_rc=$?
    printf '%s' "$out"
}

# A tree loaded or a file parsed says so, so a process answered from kept JSON is
# told apart from one that read the file.
_TBG_CANARY='_toml_cache_load() { printf "treeload "; return 1; }
_toml_parse_text() { printf "parsed "; _TOML_ERR="canary"; return 2; }'

# _tbg_proxy <dir> -> a `taplo` in <dir>/bin that logs its arguments to <dir>/log
# and runs the real one
_tbg_proxy() {
    mkdir -p "$1/bin"
    printf '#!/bin/sh\necho "$*" >> "%s/log"\nexec "%s" "$@"\n' "$1" "$(deps_path taplo)" > "$1/bin/taplo"
    chmod +x "$1/bin/taplo"
}

_tbg_taplo() { [[ "$(deps_variant taplo)" == taplo ]] && deps_can toml_json_taplo; }

#[test]
it_answers_a_large_file_from_the_json_an_earlier_process_kept() {
    local d first second; d="$(mktemp -d)"
    _tbg_file "$d/big.toml"
    first="$(_tbg_run "taplo yq" "$d/cache" "" "$d/big.toml")"
    second="$(_tbg_run "taplo yq" "$d/cache" "$_TBG_CANARY" "$d/big.toml")"
    rm -rf "$d"
    assert_eq "${first:0:30}" '{"zero":0,": colon-first":1,"a'
    assert_eq "$second" "$first"
}

#[test]
it_converts_a_large_file_again_once_its_text_changed() {
    # The positive control for the one above: the canary fires where nothing is
    # kept for this text, and the edit shows in the answer.
    local d canary changed; d="$(mktemp -d)"
    _tbg_file "$d/big.toml"
    _tbg_run "taplo yq" "$d/cache" "" "$d/big.toml" > /dev/null
    sed -i 's/"ticket_3"/"ticket_three"/' "$d/big.toml"
    canary="$(_tbg_run "taplo yq" "$d/cache" "$_TBG_CANARY" "$d/big.toml")"
    changed="$(_tbg_run "taplo yq" "$d/cache" "" "$d/big.toml")"
    rm -rf "$d"
    assert_contains "$canary" "parsed"
    assert_contains "$changed" '"key":"ticket_three"'
    assert_not_contains "$changed" '"key":"ticket_3"'
}

#[test]
it_does_not_take_a_kept_json_others_can_write() {
    # A kept JSON is printed as it is, so it is trusted as a kept tree is: the
    # reader's own, and no directory above it that others can write.
    local d at out control; d="$(mktemp -d)"
    _tbg_file "$d/big.toml"
    _tbg_run "taplo yq" "$d/cache" "" "$d/big.toml" > /dev/null
    control="$(_tbg_run "taplo yq" "$d/cache" "$_TBG_CANARY" "$d/big.toml")"
    at="$(find "$d/cache" -type f -name '*.json' | head -n 1)"
    [[ -n "$at" ]] || at="$(find "$d/cache" -type f | head -n 1)"
    chmod 666 "$at"
    out="$(_tbg_run "taplo yq" "$d/cache" "$_TBG_CANARY" "$d/big.toml")"
    rm -rf "$d"
    assert_eq "${control:0:30}" '{"zero":0,": colon-first":1,"a'
    assert_contains "$out" "parsed"
}

#[test]
it_takes_the_json_of_taplo_for_a_large_file_and_prints_it_compact() {
    _tbg_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local d floor tool; d="$(mktemp -d)"
    _tbg_file "$d/big.toml"
    _tbg_proxy "$d"
    floor="$(_tbg_run "taplo yq" "$d/c1" "" "$d/big.toml")"
    tool="$(_tbg_run "yq" "$d/c2" "" "$d/big.toml" "$d/bin")"
    local calls; calls="$(grep -c 'get' "$d/log" 2>/dev/null)"
    rm -rf "$d"
    assert_eq "$tool" "$floor"
    assert_eq "$calls" "1" "taplo was asked once for the large file"
}

#[test]
it_takes_a_large_file_with_a_digest_in_a_string_to_taplo() {
    # Nineteen digits in a row inside a string are not an integer past 64 bits,
    # and sent the whole file to the floor, which is the slow way.
    _tbg_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local d floor tool calls; d="$(mktemp -d)"
    _tbg_file "$d/big.toml" 'digest = "pre-push-1794792541456061999.log"
'
    _tbg_proxy "$d"
    floor="$(_tbg_run "taplo yq" "$d/c1" "" "$d/big.toml")"
    tool="$(_tbg_run "yq" "$d/c2" "" "$d/big.toml" "$d/bin")"
    calls="$(grep -c 'get' "$d/log" 2>/dev/null)"
    rm -rf "$d"
    assert_eq "$tool" "$floor"
    assert_contains "$tool" '"digest":"pre-push-1794792541456061999.log"'
    assert_eq "$calls" "1"
}

#[test]
it_refuses_a_large_file_with_an_integer_past_64_bits_beside_a_digest_in_a_string() {
    # taplo gives -9223372036854775809 as 0. Its digits are not in the JSON, the
    # digest's are, so the digits of the text and of the JSON differ and the
    # floor reads the file and refuses it.
    _tbg_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local d out; d="$(mktemp -d)"
    _tbg_file "$d/big.toml" 'digest = "pre-push-1794792541456061999.log"
b = -9223372036854775809
'
    _tbg_proxy "$d"
    _tbg_run "yq" "$d/c1" "" "$d/big.toml" "$d/bin" > "$d/out"
    out="$(cat "$d/out")"
    rm -rf "$d"
    assert_eq "$_tbg_rc" "2"
    assert_contains "$out" "out of range"
}

#[test]
it_gives_the_floors_text_for_a_float_in_a_large_file() {
    # taplo rewrites `1e3` as `1000.0`, so a file holding a float is the floor's.
    _tbg_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local d out; d="$(mktemp -d)"
    _tbg_file "$d/big.toml" 'f = 1e3
g = 3.0
'
    _tbg_proxy "$d"
    out="$(_tbg_run "yq" "$d/c1" "" "$d/big.toml" "$d/bin")"
    rm -rf "$d"
    assert_contains "$out" '"f":1e3,"g":3.0}'
}

#[test]
it_gives_the_floors_text_for_a_date_time_in_a_large_file() {
    # taplo gives `+00:00` as `Z`, and a string that reads as a date-time is
    # the floor's to write.
    _tbg_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local d out; d="$(mktemp -d)"
    _tbg_file "$d/big.toml" 'at = 1979-05-27T07:32:00+00:00
'
    _tbg_proxy "$d"
    out="$(_tbg_run "yq" "$d/c1" "" "$d/big.toml" "$d/bin")"
    rm -rf "$d"
    assert_contains "$out" '"at":"1979-05-27T07:32:00+00:00"}'
}

#[test]
it_keeps_a_note_that_reads_as_a_float_or_a_date_as_a_string_in_a_large_file() {
    # Not every number-shaped text is a float: a string is the string, and the
    # text of the file is converted whichever reader serves it.
    local d out; d="$(mktemp -d)"
    _tbg_file "$d/big.toml" 's = "1.5"
t = "1979-05-27"
u = "v: 2.5e3, 12:30:00"
'
    out="$(_tbg_run "taplo yq" "$d/c1" "" "$d/big.toml")"
    rm -rf "$d"
    assert_contains "$out" '"s":"1.5","t":"1979-05-27","u":"v: 2.5e3, 12:30:00"}'
}

#[test]
it_converts_a_large_file_to_the_same_text_through_every_reader() {
    # The expected text is jq's compaction of taplo's own output: a reader that
    # is not the code under test. The floor and each tool present print it.
    command -v jq > /dev/null 2>&1 || { skip "jq absent: no second opinion on the text"; return 0; }
    _tbg_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local d want got; d="$(mktemp -d)"
    _tbg_file "$d/big.toml"
    want="$("$(deps_path taplo)" get -o json < "$d/big.toml" | jq -c .)"
    got="$(_tbg_run "taplo yq" "$d/c1" "" "$d/big.toml")"
    assert_eq "$got" "$want" "the floor"
    got="$(_tbg_run "yq" "$d/c2" "" "$d/big.toml")"
    assert_eq "$got" "$want" "taplo"
    if [[ "$(deps_variant yq)" == mikefarah ]]; then
        got="$(_tbg_run "taplo" "$d/c3" "" "$d/big.toml")"
        assert_eq "$got" "$want" "mikefarah yq"
    fi
    rm -rf "$d"
}

# _tbg_sized <path> <bytes> -> a file of exactly that many bytes, one key
_tbg_sized() {
    local pad; printf -v pad '%*s' "$(( $2 - 7 ))" ''
    printf 'a = "%s"\n' "${pad// /x}" > "$1"
}

#[test]
it_takes_the_large_path_from_4096_bytes_and_the_tree_route_below() {
    # The kept JSON is what the large path leaves and the tree route does not.
    local d n first second; d="$(mktemp -d)"
    for n in 4095 4096; do
        _tbg_sized "$d/f$n.toml" "$n"
        first="$(_tbg_run "taplo yq" "$d/c$n" "" "$d/f$n.toml")"
        second="$(_tbg_run "taplo yq" "$d/c$n" "$_TBG_CANARY" "$d/f$n.toml")"
        if (( n == 4096 )); then assert_eq "$second" "$first" "4096 bytes is kept"
        else assert_contains "$second" "treeload" "4095 bytes is not"; fi
    done
    rm -rf "$d"
}

#[test]
it_refuses_an_integer_past_64_bits_on_both_sides_of_the_threshold_through_taplo() {
    # taplo echoes 9223372036854775808 and 18446744073709551615, which no
    # reader may hold; the floor refuses them, so every path does, and a refusal
    # is never kept to be answered later with taplo out of reach.
    _tbg_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local d t big out; d="$(mktemp -d)"
    _tbg_proxy "$d"
    for t in 'b = 9223372036854775808
' 'b = 18446744073709551615
' 'b = [1, 9223372036854775808]
'; do
        for big in 0 1; do
            if (( big )); then _tbg_file "$d/f.toml" "$t"; else printf '%s' "$t" > "$d/f.toml"; fi
            rm -rf "$d/c"
            _tbg_run "yq" "$d/c" "" "$d/f.toml" "$d/bin" > "$d/out"; out="$(cat "$d/out")"
            assert_eq "$_tbg_rc" "2" "taplo, big=$big, $t"
            assert_contains "$out" "out of range"
            _tbg_run "taplo yq" "$d/c" "" "$d/f.toml" > "$d/out"
            assert_eq "$_tbg_rc" "2" "taplo hidden after, big=$big"
        done
    done
    _tbg_file "$d/f.toml" 'b = 9223372036854775807
'
    out="$(_tbg_run "yq" "$d/c2" "" "$d/f.toml" "$d/bin")"
    rm -rf "$d"
    assert_contains "$out" '"b":9223372036854775807}'
}

#[test]
it_converts_the_text_it_read_where_the_file_is_swapped_for_another_meanwhile() {
    # taplo is refused, so the floor reads, and between the first read and the
    # second the file is replaced: the JSON kept under the first text must be the
    # first text's, never the second's.
    local d ref swapped again; d="$(mktemp -d)"
    _tbg_file "$d/f.toml"
    cp "$d/f.toml" "$d/orig.toml"
    ref="$(_tbg_run "taplo yq" "$d/ref" "" "$d/f.toml")"
    swapped="$(_tbg_run "taplo yq" "$d/c" '_tj_tool() { printf "swapped = 1\n" > "'"$d"'/f.toml"; return 1; }' "$d/f.toml")"
    cp "$d/orig.toml" "$d/f.toml"
    again="$(_tbg_run "taplo yq" "$d/c" "" "$d/f.toml")"
    rm -rf "$d"
    assert_eq "$swapped" "$ref"
    assert_eq "$again" "$ref"
}

#[test]
it_converts_again_where_the_taplo_that_wrote_the_kept_json_was_replaced() {
    _tbg_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local d calls; d="$(mktemp -d)"
    _tbg_file "$d/f.toml"
    _tbg_proxy "$d"
    _tbg_run "yq" "$d/c" "" "$d/f.toml" "$d/bin" > /dev/null
    _tbg_run "yq" "$d/c" "" "$d/f.toml" "$d/bin" > /dev/null
    calls="$(grep -c get "$d/log")"
    assert_eq "$calls" "1" "kept while taplo is the one that wrote it"
    touch -d "now + 10 seconds" "$d/bin/taplo"
    _tbg_run "yq" "$d/c" "" "$d/f.toml" "$d/bin" > /dev/null
    calls="$(grep -c get "$d/log")"
    rm -rf "$d"
    assert_eq "$calls" "2" "taplo is asked again once its binary is newer"
}

#[test]
it_refuses_what_the_floor_refuses_on_the_large_path_through_taplo() {
    # A NUL escape, a key holding the unit separator, inf and nan: taplo takes
    # each, and the floor does not, so the file is the floor's.
    _tbg_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local d t out; d="$(mktemp -d)"
    _tbg_proxy "$d"
    for t in 'n = "x\u0000y"
' '"k\u001fz" = 1
' 'x = inf
' 'y = nan
'; do
        _tbg_file "$d/f.toml" "$t"
        _tbg_run "yq" "$d/c$RANDOM" "" "$d/f.toml" "$d/bin" > "$d/out"
        assert_eq "$_tbg_rc" "2" "$t"
    done
    rm -rf "$d"
}

#[test]
it_cuts_a_byte_order_mark_on_the_large_path() {
    _tbg_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local d plain bom; d="$(mktemp -d)"
    _tbg_file "$d/plain.toml"
    { printf '\xef\xbb\xbf'; cat "$d/plain.toml"; } > "$d/bom.toml"
    plain="$(_tbg_run "yq" "$d/c1" "" "$d/plain.toml")"
    bom="$(_tbg_run "yq" "$d/c2" "" "$d/bom.toml")"
    rm -rf "$d"
    assert_eq "${plain:0:12}" '{"zero":0,":'
    assert_eq "$bom" "$plain"
}

#[test]
it_does_not_take_a_kept_json_that_is_a_link_or_sits_in_a_directory_others_can_write() {
    local d at first; d="$(mktemp -d)"
    _tbg_file "$d/f.toml"
    first="$(_tbg_run "taplo yq" "$d/c" "" "$d/f.toml")"
    at="$(find "$d/c" -type f -name '*.json' | head -n 1)"
    assert_eq "$(_tbg_run "taplo yq" "$d/c" "$_TBG_CANARY" "$d/f.toml")" "$first" "the control"
    cp "$at" "$d/copy"; rm -f "$at"; ln -s "$d/copy" "$at"
    assert_contains "$(_tbg_run "taplo yq" "$d/c" "$_TBG_CANARY" "$d/f.toml")" "parsed"
    rm -f "$at"
    _tbg_run "taplo yq" "$d/c" "" "$d/f.toml" > /dev/null
    chmod 775 "${at%/*}"
    assert_contains "$(_tbg_run "taplo yq" "$d/c" "$_TBG_CANARY" "$d/f.toml")" "parsed"
    chmod 700 "${at%/*}"
    rm -rf "$d"
}
