#!/usr/bin/env bash
# A unit reaching its own library, and a file knowing where it is.
#
# Both exist because of the same gap. `use foo` resolves nutshell's set and
# `use dep::foo` resolves a declared dependency, so a project had no way at all
# to name a module it wrote itself, and every consumer hand-rolled a path
# instead. Those paths were anchored on NUTSHELL_SCRIPT_DIR, which names the
# entry point rather than the file doing the asking, so they broke the moment
# the entry point moved. A whole suite went down that way.

use test

# nutshell stats the script it is given, so a process substitution reaching it as
# /dev/fd/62 is not a path it can resolve. Real file, in the unit.
run_script() {
    local dir="$1" body="$2"
    printf '%b' "$body" > "$dir/entry.sh"
    (cd "$dir" && nutshell "$dir/entry.sh" 2>&1)
}

# A throwaway unit: a nut.toml to mark it, a lib/ with a module in it.
make_unit() {
    local dir
    dir="$(mktemp -d)"
    mkdir -p "$dir/lib"
    printf '[deps]\n' > "$dir/nut.toml"
    printf 'nut_once || return 0\ngreet() { printf mine; }\n' > "$dir/lib/mine.sh"
    printf '%s' "$dir"
}

#[test]
it_reaches_a_module_this_unit_wrote() {
    local d out
    d="$(make_unit)"
    out="$(cd "$d" && run_script "$d" 'use super::mine\ngreet\n' 2>&1)"
    assert_eq "$out" "mine"
    rm -rf "$d"
}

#[test]
it_says_so_when_the_unit_has_no_such_module() {
    local d out
    d="$(make_unit)"
    out="$(cd "$d" && run_script "$d" 'use super::absent\n' 2>&1)"
    assert_contains "$out" "no module"
    rm -rf "$d"
}

# The case that must fail, and the reason `super::` does not fall through.
#
# `string` is a real nutshell module. A unit with no `lib/string.sh` that writes
# `use super::string` has to be told so rather than handed nutshell's, or it
# loads something it did not write, cannot tell, and gets whatever that module
# happens to define.
#[test]
it_does_not_fall_through_to_nutshells_own_module_of_the_same_name() {
    local d out
    d="$(make_unit)"
    out="$(cd "$d" && run_script "$d" 'use super::string\n' 2>&1)"
    assert_contains "$out" "no module"
    rm -rf "$d"
}

#[test]
it_refuses_when_there_is_no_manifest_to_mark_the_unit() {
    local d out
    d="$(mktemp -d)" # deliberately no nut.toml
    out="$(cd "$d" && run_script "$d" 'use super::mine\n' 2>&1)"
    assert_contains "$out" "nut.toml"
    rm -rf "$d"
}

#[test]
it_reports_the_calling_file_and_not_the_entry_point() {
    local d out
    d="$(mktemp -d)"
    mkdir -p "$d/lib"
    printf '[deps]\n' > "$d/nut.toml"
    printf 'nut_once || return 0\nwhere_am_i() { nut_dir; }\n' > "$d/lib/probe.sh"
    out="$(cd "$d" && run_script "$d" 'use super::probe\nwhere_am_i\n' 2>&1)"
    # The module lives in lib/ and the entry script does not, so an answer
    # derived from NUTSHELL_SCRIPT_DIR would name the entry script's directory.
    assert_contains "$out" "/lib"
    rm -rf "$d"
}

#[test]
it_gives_a_file_and_a_dir_that_agree() {
    local d out dir file
    d="$(mktemp -d)"
    mkdir -p "$d/lib"
    printf '[deps]\n' > "$d/nut.toml"
    printf 'nut_once || return 0\nboth() { printf "%%s|%%s" "$(nut_dir)" "$(nut_file)"; }\n' \
        > "$d/lib/probe.sh"
    out="$(cd "$d" && run_script "$d" 'use super::probe\nboth\n' 2>&1)"
    dir="${out%%|*}"
    file="${out##*|}"
    assert_eq "$file" "${dir}/probe.sh"
    rm -rf "$d"
}
