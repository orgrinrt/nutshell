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

# --- what was there before the interpreter stopped loading it -------------------
#
# The interpreter used to load `extern` and `log` before every script, and so
# everything they load. A script that called `log_info` with no `use` worked,
# and still does: each such function is a stub that loads its module on the
# first call, so a script that calls none of them loads nothing.

#[test]
it_logs_from_a_script_that_asked_for_no_module() {
    _st_dir || return 0
    local out; out="$(_st_run 'log_info hello')"
    rm -rf "$_ST_D"
    assert_eq "$out" "[INFO] hello"
}

#[test]
it_logs_from_a_capture_in_a_script_that_asked_for_no_module() {
    _st_dir || return 0
    local out; out="$(_st_run 'x="$(log_info hello 2>&1)"; printf "<%s>" "$x"')"
    rm -rf "$_ST_D"
    assert_eq "$out" "<[INFO] hello>"
}

#[test]
it_asks_deps_after_asking_only_for_toml() {
    _st_dir || return 0
    local out
    out="$(_st_run 'use toml; deps_has bash && printf yes; is_truthy true && printf " truthy"')"
    rm -rf "$_ST_D"
    assert_eq "$out" "yes truthy"
}

#[test]
it_asks_deps_from_a_capture_after_asking_only_for_toml() {
    _st_dir || return 0
    local out
    out="$(_st_run 'use toml; printf "<%s>" "$(deps_has bash && printf yes; is_truthy 1 && printf " truthy")"')"
    rm -rf "$_ST_D"
    assert_eq "$out" "<yes truthy>"
}

#[test]
it_still_loads_nothing_for_a_script_that_calls_none_of_them() {
    # What the stubs cost: they are there, and no module is.
    _st_dir || return 0
    local out
    out="$(_st_run 'declare -F log_info >/dev/null && printf "stub "; printf "[%s]" "$(nutshell_modules | tr "\n" " ")"')"
    rm -rf "$_ST_D"
    assert_eq "$out" "stub []"
}

#[test]
it_defines_each_stubbed_function_in_the_module_the_stub_names() {
    # A stub naming the wrong module, or a function its module no longer has,
    # would stop at the guard at the first call. Each row is checked in a bash
    # that loaded only that module.
    local table="${NUT%/bin/nutshell}/prelude.nut" init="${NUT%/bin/nutshell}/init"
    local name mod fns n=0 bad=""
    [[ -r "$table" ]] || { assert_eq "missing" "$table"; return 0; }
    while read mod fns; do
        case "$mod" in ""|"#"*) continue ;; esac
        for name in $fns; do
            n=$(( n + 1 ))
            env -i PATH="$PATH" HOME="$HOME" bash -c '. "$1" || exit 1; use "$2" >/dev/null 2>&1; declare -F "$3" >/dev/null' \
                _ "$init" "$mod" "$name" || bad+=" $name($mod)"
        done
    done < "$table"
    assert_eq "$bad" ""
    # The public functions `use extern log` defined on dev at 2173589, which
    # is what the interpreter loaded before every script there.
    assert_eq "$n" "165"
}
