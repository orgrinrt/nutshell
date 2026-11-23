#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/start-cost - What a nutshell script pays before its first line
# =============================================================================
#
# A hook that fires on every tool call pays this every time, so it decides
# whether such a hook can be a nutshell script at all. The question is where the
# time goes between the interpreter starting, `init`, the modules the
# interpreter loads for itself, `deps` setting up, and the read of a project's
# `nut.toml` for an engine pin; and whether a script that asks for nothing, or
# only for `json`, starts under the line.
#
# The targets were stated before this bench was first run: a script with no
# `use` under 50ms, one with `use json` under 80ms, per start. They are
# `bench_target`s, so a run that misses one fails.
#
# **Each start is a fresh process under `env -i`**, because the cost is paid
# once per process, and because `./bench` itself sourced `init`, whose exported
# functions a child bash would otherwise import and parse before doing
# anything. Every arm runs its start ITERS times, so the shortest arm still
# spans tens of milliseconds and the baseline's spread means something; the
# table's milliseconds are for the batch and the breakdown below it divides.
#
# Scripts run as `bin/nutshell <script>`, which is what `#!/usr/bin/env
# nutshell` execs, less one `env` lookup on PATH that every arm would share.
#
# Usage:
#   ./bench start-cost [iterations]
# =============================================================================

use bench

ITERS="${1:-10}"
ROOT="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)"

_SC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nut-start.XXXXXX")"
trap '[[ -n "${_SC_TMP:-}" ]] && rm -rf "$_SC_TMP"' EXIT
mkdir -p "$_SC_TMP/bare" "$_SC_TMP/unit"

# No manifest above the bare scripts, or the arm that is meant to find none
# would find one and price a read it was there to leave out. The interpreter
# stops its search at a `.git` or at HOME; this looks the whole way up, which is
# the stricter of the two.
_sc_dir="$_SC_TMP/bare"
while [[ -n "$_sc_dir" ]]; do
    if [[ -f "$_sc_dir/nut.toml" ]]; then
        printf 'start-cost: %s/nut.toml sits above the bare scripts\n' "$_sc_dir" >&2
        exit 1
    fi
    _sc_dir="${_sc_dir%/*}"
done

printf '#!/usr/bin/env nutshell\nprintf ok\n' > "$_SC_TMP/bare/none.sh"
printf '#!/usr/bin/env nutshell\nuse json\nprintf ok\n' > "$_SC_TMP/bare/json.sh"
printf '#!/usr/bin/env nutshell\nprintf ok\n' > "$_SC_TMP/unit/none.sh"
printf '#!/usr/bin/env nutshell\nuse toml\nprintf ok\n' > "$_SC_TMP/unit/toml.sh"
# Twenty captures of a stub, the shape a loop over paths takes: each `$(...)`
# is a subshell, and a module loaded in one is lost with it.
printf '#!/usr/bin/env nutshell\nfor i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do x="$(fs_basename /a/b)"; done\nprintf ok\n' > "$_SC_TMP/bare/captures.sh"

# A project manifest of 300 lines with no pin in it, so the interpreter's pin
# read walks all of it and finds nothing, which is what every unpinned project
# costs. Tables of the shapes a manifest holds: strings, integers, booleans and
# arrays, one table per tool the way `[tests.*]` and `[deps.*]` are laid out.
{
    printf '[package]\nname = "start-cost"\nversion = "0.1.0"\n'
    printf 'description = "a project manifest of a realistic length"\n\n'
    _sc_i=0
    while :; do
        printf '[tools.t%s]\nname = "tool-%s"\nlimit = %s\n' "$_sc_i" "$_sc_i" "$_sc_i"
        printf 'flags = ["--quiet", "--color=never"]\nenabled = true\n\n'
        _sc_i=$(( _sc_i + 1 ))
        (( _sc_i * 6 + 5 >= 300 )) && break
    done
    printf '[end]\ndone = true\n'
} | head -n 300 > "$_SC_TMP/unit/nut.toml"
_SC_LINES="$(wc -l < "$_SC_TMP/unit/nut.toml" | tr -d ' ')"

# The child's whole environment. PATH is kept so `bash` and the tools resolve as
# they do for anybody; nothing nutshell exported comes through.
_sc_run() {
    local i last=""
    for (( i = 0; i < ITERS; i++ )); do
        last="$(env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" "$@" 2>/dev/null)"
    done
    printf '%s' "$last"
}


# The same start with nothing kept from an earlier one: each start gets a cache
# directory of its own that does not exist yet, so the pin read parses the
# manifest and writes its tree. Named apart per start, since emptying one
# would be a fork inside the time.
_SC_COLD="$_SC_TMP/cold"
_sc_run_cold() {
    local i last=""
    for (( i = 0; i < ITERS; i++ )); do
        last="$(env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
            XDG_CACHE_HOME="${_SC_COLD}/${i}.${SRANDOM:-$RANDOM}.${RANDOM}" "$@" 2>/dev/null)"
    done
    printf '%s' "$last"
}
# The interpreter alone: a bash that prints and exits.
arm_bash()          { _sc_run bash -c 'printf ok'; }
# `init` sourced, no module asked for.
arm_init()          { _sc_run bash -c '. "$1/init" || exit 1; printf ok' _ "$ROOT"; }
# `init` and `deps`, which every tool-picking module loads first.
arm_deps()          { _sc_run bash -c '. "$1/init" || exit 1; use deps; printf ok' _ "$ROOT"; }
# `init` and what `bin/nutshell` loaded for itself before this bench was
# written: `extern` for the pin's mirror and `log` for its warnings.
arm_preload()       { _sc_run bash -c '. "$1/init" || exit 1; use extern log; printf ok' _ "$ROOT"; }
# A script, run by the interpreter, with no `use` and no manifest above it.
arm_bare()          { _sc_run "$ROOT/bin/nutshell" "$_SC_TMP/bare/none.sh"; }
# The same script beside a 300-line `nut.toml`: the difference is the pin read.
arm_bare_manifest() { _sc_run "$ROOT/bin/nutshell" "$_SC_TMP/unit/none.sh"; }
# `use json`, no manifest.
arm_json()          { _sc_run "$ROOT/bin/nutshell" "$_SC_TMP/bare/json.sh"; }
# `use toml` beside the 300-line `nut.toml`.
arm_toml()          { _sc_run "$ROOT/bin/nutshell" "$_SC_TMP/unit/toml.sh"; }
# Twenty `$(fs_basename)` with no `use`, no manifest.
arm_captures()      { _sc_run "$ROOT/bin/nutshell" "$_SC_TMP/bare/captures.sh"; }
# No `use` beside the manifest, with no tree kept for it.
arm_bare_cold()     { _sc_run_cold "$ROOT/bin/nutshell" "$_SC_TMP/unit/none.sh"; }

_answer_of() { "$1"; }

bench_case "What a nutshell script pays before its first line, ${ITERS} starts per arm"
bench_size "$ITERS"
bench_verify _answer_of

bench_arm "bash, nothing loaded"              arm_bash
bench_arm "bash sourcing init"                arm_init
bench_arm "init, use deps"                    arm_deps
bench_arm "init, use extern log"              arm_preload
bench_arm "script, no use, no manifest"       arm_bare
bench_arm "script, no use, ${_SC_LINES}-line manifest" arm_bare_manifest
bench_arm "script, use json, no manifest"     arm_json
bench_arm "script, use toml, ${_SC_LINES}-line manifest" arm_toml
bench_arm "script, no use, ${_SC_LINES}-line manifest, cold" arm_bare_cold
bench_arm "script, 20 captures of a stub, no manifest" arm_captures

bench_target arm_bare          $(( 50 * ITERS ))
bench_target arm_bare_manifest $(( 50 * ITERS ))
bench_target arm_json          $(( 80 * ITERS ))

bench_run; _sc_rc=$?

# Per start, and the differences that say where it went. Only for a run whose
# controls passed: the verdicts are written after them and not before.
if (( _sc_rc == 0 || ${#_BENCH_VERDICT[@]} > 0 )); then
    _sc_per() { printf '%d.%d' $(( $1 / ITERS )) $(( $1 * 10 / ITERS % 10 )); }
    _sc_diff() {
        local d=$(( _BENCH_BESTS[$1] - _BENCH_BESTS[$2] ))
        (( d < 0 )) && { printf -- '-'; d=$(( -d )); }
        _sc_per "$d"
    }
    printf '\nPer start, best of %s batches of %s:\n\n' "$BENCH_REPEATS" "$ITERS"
    for (( _sc_j = 0; _sc_j < ${#_BENCH_LABEL[@]}; _sc_j++ )); do
        printf '  %-44s %7s ms\n' "${_BENCH_LABEL[$_sc_j]}" "$(_sc_per "${_BENCH_BESTS[$_sc_j]}")"
    done
    printf '\nWhere it goes, per start:\n\n'
    printf '  %-44s %7s ms\n' "the interpreter starting"            "$(_sc_per "${_BENCH_BESTS[0]}")"
    printf '  %-44s %7s ms\n' "init"                                "$(_sc_diff 1 0)"
    printf '  %-44s %7s ms\n' "deps setting up"                     "$(_sc_diff 2 1)"
    printf '  %-44s %7s ms\n' "use extern log"                      "$(_sc_diff 3 1)"
    printf '  %-44s %7s ms\n' "bin/nutshell beyond init"            "$(_sc_diff 4 1)"
    printf '  %-44s %7s ms\n' "the pin read, ${_SC_LINES}-line manifest" "$(_sc_diff 5 4)"
    printf '  %-44s %7s ms\n' "use json"                            "$(_sc_diff 6 4)"
    printf '  %-44s %7s ms\n' "use toml, beyond the pin read"       "$(_sc_diff 7 5)"
    printf '  %-44s %7s ms\n' "the pin read with no tree kept"      "$(_sc_diff 8 4)"
fi
exit "$_sc_rc"
