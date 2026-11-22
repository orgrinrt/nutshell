#!/usr/bin/env bash
# Tests for the toml backend layer: every backend reads every fixture of
# `tests/fixtures/toml/` to the same values, and the one picked is never the
# python `yq`.
#
# A backend is picked through `deps`, so each run is a script in a unit of its
# own whose `[deps.paths]` points `yq` and `taplo` at the tool under test or at
# a fake that cannot serve. The expected JSON is taplo's output on each fixture
# put through `jq -c`, written in here, the byte order mark cut first for
# `bom.toml`, since neither tool reads one.

use deps test toml

FIX="${NUTSHELL_ROOT}/tests/fixtures/toml"

# fixture <TAB> its JSON
_TB_JSON='aot_twice	{"p":[{"name":"a"},{"name":"b"}]}
array_of_tables	{"products":[{"name":"Hammer","sku":738594937},{},{"name":"Nail","sku":284758393}],"servers":[{"name":"alpha","opts":{"fast":true}},{"name":"beta"}]}
bom	{"title":"bom","next":2}
dotted_keys	{"fruit":{"apple":{"color":"red","size":3},"banana":"yellow"},"server":{"net":{"port":80,"host":"localhost"}}}
inline_table	{"i":{"x":1,"y":"two"},"n":{"a":{"b":1},"c":{"d":"e"}},"empty":{},"pts":[{"x":1},{"x":2}]}
ml_array	{"a":[1,2,3],"nested":[["x","y"],["z"]],"z":3}
ml_fold	{"folded":"The quick brown fox.","kept":"a\\\nb"}
ml_string	{"ml":"line one\nline \"two\" with \"\"quotes\"\"\n","lit":"raw \\n kept\n","after":1}
padded_header	{"sp":{"k":2},"outer":{"inner":{"k":5}}}
quoted_dot_key	{"quoted.dot":"root","site":{"google.com":true},"hosts":{"a.b":"dotted"}}
quoted_headers	{"quoted sect":{"k":1},"a":{"b.c":{"d":{"k":3}}},"lit sect":{"k":4}}
quoted_keys	{"quoted key":1,"lit key":2,"bare-key_1":3,"escAped":4}
types	{"i":1000,"h":255,"o":15,"neg":-3,"pi":7,"f":3.14,"fu":1000.5,"t":true,"dt":"1979-05-27T07:32:00Z","do":"1979-05-27T00:32:00.999-07:00"}'

# fixture <TAB> path <TAB> what `toml_get` prints, from the JSON above
_TB_GET='aot_twice	p.1.name	b
array_of_tables	products.2.sku	284758393
array_of_tables	servers.0.opts.fast	true
bom	title	bom
dotted_keys	fruit.apple.color	red
dotted_keys	server.net.port	80
inline_table	n.c.d	e
inline_table	pts.1.x	2
ml_array	nested.0.1	y
ml_array	a.2	3
ml_fold	folded	The quick brown fox.
padded_header	outer.inner.k	5
quoted_dot_key	"quoted.dot"	root
quoted_dot_key	site."google.com"	true
quoted_headers	a."b.c".d.k	3
quoted_keys	quoted key	1
types	h	255
types	fu	1000.5
types	do	1979-05-27T00:32:00.999-07:00'

# Fixtures a tool fails on, so the bash floor answers for it: mikefarah yq
# 4.44.3 panics on `array_of_tables.toml`.
_TB_TOOL_FAILS='yq array_of_tables'

# A tool that answers `--version` with a line, logs every other call, and fails
# it, so it can serve no file.
_tb_fake() {
    local file="$1" ver="$2" log="$3"
    {
        printf '#!/bin/sh\n'
        printf 'case "$*" in\n  *--version*) echo '"'"'%s'"'"' ;;\n' "$ver"
        printf '  *) echo "$*" >> "%s"; exit 1 ;;\nesac\n' "$log"
    } > "$file"
    chmod +x "$file"
}

# _tb_run <dir> <yq path> <taplo path> -> runs the reader script in a unit whose
# `[deps.paths]` names those two, and prints what it printed
_tb_run() {
    local d="$1"
    mkdir -p "$d/sub"
    printf '[deps.paths]\nyq = "%s"\ntaplo = "%s"\n' "$2" "$3" > "$d/nut.toml"
    cat > "$d/sub/s.sh" <<'EOF'
use toml toml::json
fix="$1"
for f in "$fix"/*.toml; do
    n="${f##*/}"; n="${n%.toml}"
    printf 'json\t%s\t%s\n' "$n" "$(toml_to_json "$f")"
    printf 'from\t%s\t%s\n' "$n" "$_TOML_FROM"
done
while IFS=$'\t' read -r n p _; do
    printf 'get\t%s\t%s\t%s\n' "$n" "$p" "$(toml_get "$fix/$n.toml" "$p")"
done <<< "$2"
printf 'backend\t%s\n' "$_TOML_BACKEND"
EOF
    ( cd / && "${NUTSHELL_ROOT}/bin/nutshell" "$d/sub/s.sh" "$FIX" "$_TB_GET" 2>&1 )
}

# _tb_check <backend> <output> -> asserts the backend ran and read every fixture
# to the expected JSON and values, from its own JSON where the tool served
_tb_check() {
    local be="$1" out="$2" n j p v want_from
    assert_contains "$out" "backend	${be}"
    while IFS=$'\t' read -r n j; do
        assert_contains "$out" "json	${n}	${j}"
        want_from=json
        [[ "$be" == bash || " ${_TB_TOOL_FAILS} " == *" ${be} ${n} "* ]] && want_from=bash
        assert_contains "$out" "from	${n}	${want_from}"
    done <<< "$_TB_JSON"
    while IFS=$'\t' read -r n p v; do
        assert_contains "$out" "get	${n}	${p}	${v}"
    done <<< "$_TB_GET"
}

#[test]
it_reads_every_fixture_alike_through_mikefarah_yq() {
    [[ "$(deps_variant yq)" == mikefarah ]] && deps_can toml_read \
        || { skip "mikefarah yq absent: no yq that reads TOML here"; return 0; }
    local t; t="$(mktemp -d)"
    _tb_fake "$t/taplo" 'something 1.0' "$t/log"
    _tb_check yq "$(_tb_run "$t/u" "$(deps_path yq)" "$t/taplo")"
    rm -rf "$t"
}

#[test]
it_reads_every_fixture_alike_through_taplo() {
    deps_can toml_json_taplo || { skip "taplo absent: no taplo that prints TOML as json here"; return 0; }
    local t; t="$(mktemp -d)"
    _tb_fake "$t/yq" 'yq 0.0.0' "$t/log"
    _tb_check taplo "$(_tb_run "$t/u" "$t/yq" "$(deps_path taplo)")"
    rm -rf "$t"
}

#[test]
it_reads_every_fixture_alike_through_the_bash_floor() {
    local t; t="$(mktemp -d)"
    _tb_fake "$t/yq" 'yq 0.0.0' "$t/log"
    _tb_fake "$t/taplo" 'something 1.0' "$t/log"
    _tb_check bash "$(_tb_run "$t/u" "$t/yq" "$t/taplo")"
    rm -rf "$t"
}

#[test]
it_never_reads_through_the_python_yq() {
    # The python `yq` is asked its version and nothing else, and the backend
    # is taplo where one serves, else the floor.
    local t out; t="$(mktemp -d)"
    _tb_fake "$t/yq" 'yq 0.0.0' "$t/yq.log"
    _tb_fake "$t/taplo" 'something 1.0' "$t/taplo.log"
    out="$(_tb_run "$t/u" "$t/yq" "$t/taplo")"
    assert_contains "$out" "backend	bash"
    assert_eq "$(cat "$t/yq.log" 2>/dev/null)" ""
    if deps_can toml_json_taplo; then
        out="$(_tb_run "$t/v" "$t/yq" "$(deps_path taplo)")"
        assert_contains "$out" "backend	taplo"
        assert_eq "$(cat "$t/yq.log" 2>/dev/null)" ""
    fi
    rm -rf "$t"
}

#[test]
it_reads_a_file_again_once_it_changed() {
    # The JSON is kept for the life of the process, so an edit has to be seen.
    local d; d="$(mktemp -d)"
    printf 'a = 1\n' > "$d/t.toml"
    toml_get "$d/t.toml" a > "$d/o1"
    printf 'a = 2\n' > "$d/t.toml"
    toml_get "$d/t.toml" a > "$d/o2"
    assert_eq "$(cat "$d/o1")/$(cat "$d/o2")" "1/2"
    rm -rf "$d"
}
