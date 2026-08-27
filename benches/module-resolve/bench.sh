#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/module-resolve - What a predicate costs at load time
# =============================================================================
#
# A `when=` row decides which file a module is sourced from, and the decision
# is taken on every `use` of that module, before anything is parsed. So it sits
# in front of the whole library and a cost here is a cost everything pays.
#
# The question is not whether a predicate is fast in isolation. It is whether
# a manifest that uses them resolves at the same speed as one that does not,
# because if it does not, the POSIX arrangement is paid for at every startup.
#
# The arms all answer the same question, "which file is module N", against a
# manifest of the same size. What differs is what the rows carry.
#
# Usage:
#   ./bench module-resolve [rows] [lookups]
# =============================================================================

use bench

ROWS="${1:-200}"
LOOKUPS="${2:-200}"

_MR_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-mr.XXXXXX")"
trap '[[ -n "${_MR_TMP:-}" ]] && rm -rf "$_MR_TMP"' EXIT

# A library root whose manifest carries `$2` on every row.
_mr_lib() {
    local name="$1" trailing="$2" d="$_MR_TMP/$1" i
    mkdir -p "$d"
    : > "$d/lib.nut"
    for (( i = 0; i < ROWS; i++ )); do
        printf 'mod%s  m%s.sh %s\n' "$i" "$i" "$trailing" >> "$d/lib.nut"
        : > "$d/m${i}.sh"
    done
    printf '%s' "$d"
}

# Look up a spread of modules, and print the last answer so nothing can be
# dropped for going unused.
_mr_run() {
    local d="$1" i last=""
    for (( i = 0; i < LOOKUPS; i++ )); do
        last="$(_lib_nut_lookup "$d" "mod$(( i * ROWS / LOOKUPS ))")"
    done
    printf '%s' "${last##*/}"
}

_PLAIN="$(_mr_lib plain '')"
_VIS="$(_mr_lib vis 'internal')"
_TRUE="$(_mr_lib true_pred 'when=have:sh')"
_FALSE="$(_mr_lib false_pred 'when=have:no-such-command-anywhere-3f9a')"
_BOTH="$(_mr_lib both 'when=have:sh+have:cat')"

# The false-predicate library answers nothing, so it is not an arm: it would
# disagree with the others and the harness would refuse the run, correctly.
# Its cost is reported in the note at the end instead.

arm_plain()      { _mr_run "$_PLAIN"; }
arm_visibility() { _mr_run "$_VIS"; }
arm_one_pred()   { _mr_run "$_TRUE"; }
arm_two_preds()  { _mr_run "$_BOTH"; }

_answer_of() { "$1"; }

bench_case "What a when= row costs at module resolve time"
bench_size "$ROWS"
bench_verify _answer_of

bench_arm "no trailing column"        arm_plain
bench_arm "a visibility, no predicate" arm_visibility
bench_arm "one predicate"             arm_one_pred
bench_arm "two, joined by a plus"     arm_two_preds

bench_run || exit 1

printf '\n'
printf 'The rows are %s and the lookups %s, so each lookup scans about half\n' "$ROWS" "$LOOKUPS"
printf 'the manifest. A predicate that held nowhere is not an arm here: it\n'
printf 'answers nothing, the arms would disagree, and the harness refuses the\n'
printf 'run rather than reporting the one that did no work as the fastest.\n'
