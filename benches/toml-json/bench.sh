#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/toml-json - What `toml_to_json` costs on a large file
#
# The workspace's task tracker reads about 4 MB of TOML per run, thousands of
# `[[action]]` tables of string keys and long strings. Converting that to JSON
# cost about 1.2 s per MB, which kept a port of the tracker from python blocked.
# So this bench prices the conversion on the tracker's shape at two sizes, 1 MB
# and 4 MB, through each reader `toml` can pick, each in a fresh process under
# `env -i` because the cost is paid once per process.
#
# **Cold and warm are different questions.** Cold is a process that has never
# seen the file's text: the reader parses it. Warm is a process that finds what
# an earlier process kept for the same text, `lib/toml/cache.sh`. The tracker
# runs warm nearly always and cold once per edit, so both are arms; each cold
# start gets a cache directory of its own that does not exist yet.
#
# The readers are picked by hiding the others from `deps` through
# `NUT_DEPS_HIDE`, the way the hide list is meant to be used, so the arm is the
# pick `toml` itself makes. An arm whose tool is absent is left out of the
# agreement and the timing, and the table says so.
#
# The file is generated here, deterministically, in the tracker's shape: an
# `[[action]]` table of six or seven string keys, a note of about 700 bytes
# written as one basic string with `\n` and `\"` escapes, and every seventh
# entry a `"""` string over several lines. No float and no date-time, since the
# tracker holds none and a backend hands either to the floor anyway.
#
# The targets were stated before the work on the conversion: 4 MB under 2 s on
# the floor alone, and under 0.5 s where taplo is present, on an idle machine.
#
# mikefarah yq is held to the 1 MB case: it reads 1 MB in about 17 s through
# the tree and 4 MB would take minutes per start, which is itself the result.
#
# Usage:
#   ./bench toml-json [repeats] [sizes in MB, "1 4" by default]
# =============================================================================

use bench deps

BENCH_REPEATS="${1:-${BENCH_REPEATS:-3}}"
SIZES="${2:-1 4}"
ROOT="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"

_TJ_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nut-tomljson.XXXXXX")"
trap '[[ -n "${_TJ_TMP:-}" ]] && rm -rf "$_TJ_TMP"' EXIT
mkdir -p "$_TJ_TMP/cold"

# _tj_gen <bytes> <file> -> a tracker-shaped file of at least that many bytes
_tj_gen() {
    local want="$1" file="$2" i=0 chunk="" size=0 key
    local note='Commits 1a00511d and 42599414 on main carry the state file at 5814 and 249840 lines from the coordinator doubling sets; #2874 restored it and #2875 guards the set. Every clone fetches the blob, and removing it needs a history rewrite of main, which is op'"'"'s call.\n\nMoved from the kaski ticket registry (kind question). State at the move: waiting at 2026-10-31T16:34:50Z by coord, held by op.\nOptions: leave it; rewrite main to drop the blob; fold into the orphan data tree work\nRepos: clause-dev\nSubjects: workflow\nOp said, verbatim: \"file a ticket that is primarily mine, but it is something you have to carry\".'
    : > "$file"
    while (( size < want )); do
        key="a_ticket_about_thing_number_${i}_in_the_workspace_lane"
        chunk+="[[action]]"$'\n'
        chunk+="key = \"${key}\""$'\n'
        chunk+="what = \"a ticket about thing number ${i} in the workspace lane, with a long enough title\""$'\n'
        chunk+='owner = "op"'$'\n'
        chunk+='lane = "tickets-workspace"'$'\n'
        chunk+="done_when = \"file..shared/tickets/closed/${key}\""$'\n'
        (( i % 5 )) || chunk+="source = \"kaski@f1a2e3cc7f40:mock/registry/ticket/items/${key}.toml\""$'\n'
        chunk+="note = \"entry ${i}: ${note}\""$'\n'
        if (( i % 7 == 0 )); then
            chunk+='detail = """'$'\n'
            chunk+="The detail of ${i}, over several lines."$'\n'
            chunk+='A second line, with a "quote" and a back\\slash folded \'$'\n'
            chunk+='   into the one before it.'$'\n'
            chunk+='"""'$'\n'
        fi
        chunk+=$'\n'
        i=$(( i + 1 ))
        if (( i % 100 == 0 )); then
            printf '%s' "$chunk" >> "$file"
            chunk=""
            size="$(wc -c < "$file")"
        fi
    done
    printf '%s' "$chunk" >> "$file"
}


# One start of `toml_to_json` over a file, as the answer's checksum.
# <hidden tools> <cache directory> <file>
_tj_child() {
    env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
        XDG_CACHE_HOME="$2" NUT_DEPS_HIDE="$1" \
        bash -c '. "$1/init" || exit 1; use toml::json; toml_to_json "$2" | cksum' _ "$ROOT" "$3"
}
_tj_cold() { _tj_child "$1" "$_TJ_TMP/cold/${SRANDOM:-$RANDOM}.${RANDOM}" "$2"; }
_tj_warm() { _tj_child "$1" "$_TJ_TMP/warm" "$2"; }

_TJ_FILE=""
arm_floor_cold()  { _tj_cold "taplo yq" "$_TJ_FILE"; }
arm_floor_warm()  { _tj_warm "taplo yq" "$_TJ_FILE"; }
arm_taplo_cold()  { _tj_cold "yq" "$_TJ_FILE"; }
arm_taplo_warm()  { _tj_warm "yq" "$_TJ_FILE"; }
arm_yq_cold()     { _tj_cold "taplo" "$_TJ_FILE"; }
arm_yq_warm()     { _tj_warm "taplo" "$_TJ_FILE"; }
_answer_of() { "$1"; }

use deps
_TJ_HAS_TAPLO=0 _TJ_HAS_YQ=0
{ deps_has taplo >/dev/null && [[ "$(deps_variant taplo)" == taplo ]]; } && _TJ_HAS_TAPLO=1
{ deps_has yq >/dev/null && [[ "$(deps_variant yq)" == mikefarah ]]; } && _TJ_HAS_YQ=1

# _tj_declare <arm> <label> <present> <why absent>
_tj_declare() {
    if (( $3 )); then
        bench_arm "$2" "$1"
    else
        eval "$1() { printf SKIP; }"
        bench_arm "$2" "$1" 1 "$4"
    fi
}

_tj_case() {
    local label="$1" file="$2" kb="$3" top="$4" has_yq="$5" rc=0
    _TJ_FILE="$file"
    rm -rf "$_TJ_TMP/warm"
    # Kept by one start before any is timed: what a warm start finds.
    arm_floor_warm >/dev/null
    (( _TJ_HAS_TAPLO )) && arm_taplo_warm >/dev/null
    (( has_yq ))        && arm_yq_warm >/dev/null
    bench_case "toml_to_json over ${label} of tracker-shaped TOML, ${BENCH_REPEATS} starts per arm"
    bench_size "$kb"
    bench_verify _answer_of
    bench_arm "floor, cold"                      arm_floor_cold
    bench_arm "floor, warm"                      arm_floor_warm
    _tj_declare arm_taplo_cold "taplo, cold"     "$_TJ_HAS_TAPLO" "no taplo"
    _tj_declare arm_taplo_warm "taplo, warm"     "$_TJ_HAS_TAPLO" "no taplo"
    _tj_declare arm_yq_cold    "mikefarah yq, cold" "$has_yq" "not run past 1 MB, or no mikefarah yq"
    _tj_declare arm_yq_warm    "mikefarah yq, warm" "$has_yq" "not run past 1 MB, or no mikefarah yq"
    if (( top )); then
        bench_target arm_floor_cold 2000
        bench_target arm_floor_warm 2000
        (( _TJ_HAS_TAPLO )) && bench_target arm_taplo_cold 500
        (( _TJ_HAS_TAPLO )) && bench_target arm_taplo_warm 500
    fi
    bench_run || rc=$?
    bench_reset
    return "$rc"
}

_tj_rc=0
for _tj_mb in $SIZES; do
    _tj_file="$_TJ_TMP/${_tj_mb}mb.toml"
    _tj_gen "$(( _tj_mb * 1000000 ))" "$_tj_file"
    _tj_top=0 _tj_yq=$_TJ_HAS_YQ
    (( _tj_mb >= 4 )) && _tj_top=1
    (( _tj_mb > 1 )) && _tj_yq=0
    _tj_case "${_tj_mb} MB" "$_tj_file" "$(( _tj_mb * 1000 ))" "$_tj_top" "$_tj_yq" || _tj_rc=1
done
exit "$_tj_rc"
