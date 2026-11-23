#!/usr/bin/env bash
# Tests for what a script loads before its first line.
#
# `benches/start-cost` times a start and holds it to a target; these say which
# modules are there when the script's first line runs, which is the mechanism
# under the number and does not depend on the machine. A start that loads
# nothing it was not asked for is what lets a hook on every tool call be a
# nutshell script at all.
#
# Each script runs under `env -i`, so nothing the test process loaded or
# exported reaches it, and from a directory with no `nut.toml` above it unless
# the test writes one.

use test

NUT="${BASH_SOURCE[0]%/*}/../bin/nutshell"

_st_dir() {
    _ST_D="$(mktemp -d "${TMPDIR:-/tmp}/nut-startup.XXXXXX")"
    local d="$_ST_D"
    while [[ -n "$d" ]]; do
        [[ -f "$d/nut.toml" ]] && { rm -rf "$_ST_D"; skip "a nut.toml sits above ${TMPDIR:-/tmp}"; return 1; }
        d="${d%/*}"
    done
    return 0
}

# _st_run <script body> -> what the script printed, run by the interpreter
_st_run() {
    printf '#!/usr/bin/env nutshell\n%s\n' "$1" > "$_ST_D/s.sh"
    env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" \
        XDG_CACHE_HOME="$_ST_D/cache" "$NUT" "$_ST_D/s.sh" 2>&1
}

#[test]
it_loads_no_module_for_a_script_that_asks_for_none() {
    _st_dir || return 0
    local out; out="$(_st_run 'printf "[%s]" "$(nutshell_modules | tr "\n" " ")"')"
    rm -rf "$_ST_D"
    assert_eq "$out" "[]"
}

#[test]
it_loads_neither_extern_nor_log_for_a_script_beside_an_unpinned_manifest() {
    # The interpreter reads the manifest for an engine pin. Where there is none
    # it needs neither the mirror nor anything to warn with.
    _st_dir || return 0
    printf '[package]\nname = "x"\nversion = "0.1.0"\n' > "$_ST_D/nut.toml"
    local out
    out="$(_st_run 'nutshell_loaded extern && printf extern; nutshell_loaded log && printf log; printf done')"
    rm -rf "$_ST_D"
    assert_eq "$out" "done"
}

#[test]
it_runs_a_script_that_asks_for_a_module_after_loading_none() {
    # The positive control: a start that loads nothing still gives the script
    # everything it asks for.
    _st_dir || return 0
    local out; out="$(_st_run 'use log string; str_upper ok')"
    rm -rf "$_ST_D"
    assert_eq "$out" "OK"
}
