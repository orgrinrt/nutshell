#!/usr/bin/env bash
# Tests for the bash floor.
#
# `init` uses `declare -A`, which bash 3 does not have, so it refuses to load
# on anything below 4. macOS ships 3.2 at /bin/bash and this is a tool reached
# for when a machine is already broken, so the refusal has to be readable
# rather than a syntax error two hundred lines further down.
#
# The refusal had no test at all. It was written wrong twice while being
# reviewed, and both times it was caught by hand rather than by anything that
# runs again.
#
# The version is faked rather than the shell. `BASH_VERSION` is an ordinary
# assignable variable, so the guard can be driven through every branch under
# the bash that is already running, which is what makes the table below cheap
# enough to be exhaustive.

use test

INIT="${BASH_SOURCE[0]%/*}/../init"
NUT="${BASH_SOURCE[0]%/*}/../bin/nutshell"

# The pattern the guard actually uses, read out of the file rather than copied
# here. Copying it would make this a test of the copy: edit `init` to accept
# bash 2 and the copy would keep reporting a refusal.
# The `case` label the guard actually uses, read out of the file rather than
# copied here. Copying it would make the table a test of the copy: edit `init`
# to accept bash 2 and the copy would keep reporting a refusal.
#
# Anchored on the `case` line rather than on the message, because the two
# entry points spell the message differently: `init` calls a function and the
# binary writes it inline, since it has no library to call into yet.
_guard_pattern() {
    local f="${1:-$INIT}" n
    n="$(grep -n 'case "\${BASH_VERSION' "$f" | head -1)"
    [[ -n "$n" ]] || return 1
    n="${n%%:*}"
    sed -n "$(( n + 1 ))p" "$f" | sed 's/^[[:space:]]*//; s/)[[:space:]]*$//'
}

# Bash sets `BASH_VERSION` itself at startup, so handing it in the environment
# does nothing: the new shell overwrites it before reading a line. It is an
# ordinary assignable variable once that shell is running, so every driver
# below assigns it inside the shell under test rather than in front of it.
#
# This was written the other way first. All four tests using it failed, which
# is the only reason it is written down here instead of being a thing that
# quietly reported a pass.
_as_bash3() {
    local body="$1"; shift
    bash -c "BASH_VERSION='3.2.57(1)-release'; $body" _ "$@"
}

#[test]
it_reads_its_own_guard_out_of_init() {
    # The control for the table below. If the extraction stops finding the
    # label, every row falls through to `allow` and the table reports a clean
    # pass over a guard that is not there.
    local pat; pat="$(_guard_pattern)"
    assert_ne "$pat" ""
    assert_contains "$pat" '3.*'
}

#[test]
it_carries_the_same_floor_in_both_entry_points() {
    # `bin/nutshell` has its own copy, because it is a script rather than a
    # sourced file and has no `init` to ask yet. A copy is a thing that drifts,
    # so the two labels are compared rather than assumed equal.
    assert_eq "$(_guard_pattern "$NUT")" "$(_guard_pattern "$INIT")"
}

#[test]
it_refuses_every_bash_below_four_and_no_others() {
    local pat; pat="$(_guard_pattern)"
    local v want got

    # Each row is a version string and what the guard owes it. The interesting
    # ones are the ends: an empty `BASH_VERSION` means the file is being read
    # by something that is not bash at all, and `10.0.0` is the row that says
    # `1.*` is a prefix of `1.` rather than of `1`.
    for v in '' 1.14.7 2.05b '3.2.57(1)-release' 3.0 4.0 '4.0.0-beta' \
             '4.4.20(1)-release' 5.2.15 5.3 10.0.0 11.2.3; do
        case "$v" in ''|1.*|2.*|3.*) want=refuse ;; *) want=allow ;; esac

        got=allow
        eval "case \"\$v\" in $pat) got=refuse ;; esac"

        assert_eq "$got" "$want" "BASH_VERSION=[$v]"
    done
}

#[test]
it_says_what_is_wrong_and_where_a_newer_one_comes_from() {
    # A refusal nobody can act on is a crash with better manners. The message
    # has to carry the version it found and the reason macOS specifically hits
    # this, because macOS is where it happens.
    local out
    out="$(_as_bash3 '. "$1" 2>&1 >/dev/null' "$INIT")"

    assert_contains "$out" "bash 4.0 or newer"
    assert_contains "$out" "3.2.57"
    assert_contains "$out" "macOS"
    assert_contains "$out" "PATH"
}

#[test]
it_loads_nothing_when_it_refuses() {
    # The refusal has to stop the load, not merely complain about it. A file
    # that prints the message and then defines half a library is worse than
    # one that fails outright, because the caller carries on.
    local out
    out="$(_as_bash3 '
        . "$1" >/dev/null 2>&1
        declare -F nut_once >/dev/null && echo LOADED
        printf "%s" "${_NUTSHELL_INIT:-unset}"
    ' "$INIT")"

    assert_eq "$out" "unset"
}

#[test]
it_loads_normally_on_the_bash_running_this() {
    # The control for the two above. The guard refusing everything would pass
    # both of them, and a floor that refuses every bash is not a floor.
    local out
    out="$(bash -c '. "$1" >/dev/null 2>&1 || exit 1; printf "%s" "${_NUTSHELL_INIT:-unset}"' _ "$INIT")"
    assert_eq "$out" "1"
}

#[test]
it_stops_a_caller_that_checks_the_source_line() {
    # `return` inside a sourced file returns to whoever sourced it. It cannot
    # stop them, which is why every example in the readme ends its source line
    # in `|| exit 1`. This pins that the guarded form does stop.
    local script; script="$(mktemp)"
    cat > "$script" <<'INNER'
BASH_VERSION='3.2.57(1)-release'
. "$1" || exit 1
echo REACHED_THE_BODY
INNER

    local out rc=0
    out="$(bash "$script" "$INIT" 2>/dev/null)" || rc=$?
    rm -f "$script"

    assert_eq "$out" ""
    assert_ne "$rc" "0"
}

#[test]
it_does_not_stop_a_caller_that_does_not_check() {
    # The residue, recorded rather than wished away. An unguarded source line
    # gets the message and carries on with nothing loaded, and the only fix
    # available to `init` is the one above, on the caller's side.
    local script; script="$(mktemp)"
    cat > "$script" <<'INNER'
BASH_VERSION='3.2.57(1)-release'
. "$1"
echo REACHED_THE_BODY
INNER

    local out
    out="$(bash "$script" "$INIT" 2>/dev/null)"
    rm -f "$script"

    assert_eq "$out" "REACHED_THE_BODY"
}

#[test]
it_puts_the_binarys_floor_above_anything_bash_three_cannot_parse() {
    # A guard below the first `declare -A` or `[[ ]]` is a guard the shell
    # never reaches: bash 3 fails parsing the file before running any of it,
    # and the reader gets a syntax error instead of the message.
    #
    # Faking the version cannot catch this, because the running bash parses
    # the file fine. So the check is positional, and `bash --posix -n` is the
    # cheapest reader that objects to the same constructs.
    local guard_line body_line
    guard_line="$(grep -n 'case "\${BASH_VERSION' "$NUT" | head -1)"
    guard_line="${guard_line%%:*}"
    assert_ne "$guard_line" ""

    # The first line using something bash 3 does not have, or the first
    # line of the body, whichever comes first.
    body_line="$(grep -n 'declare -A\|set -uo pipefail' "$NUT" | head -1)"
    body_line="${body_line%%:*}"
    assert_ne "$body_line" ""

    [[ "$guard_line" -lt "$body_line" ]] \
        || _test_failed "guard at line $guard_line sits below line $body_line"
}

#[test]
it_writes_the_refusal_where_a_terminal_will_show_it() {
    # stderr, so a caller piping stdout somewhere still sees why nothing came
    # out of it. The message going to stdout would land in whatever file the
    # caller was redirecting into.
    local on_out on_err
    on_out="$(_as_bash3 '. "$1" 2>/dev/null' "$INIT")"
    on_err="$(_as_bash3 '. "$1" 2>&1 >/dev/null' "$INIT")"

    assert_empty "$on_out"
    assert_contains "$on_err" "bash 4.0 or newer"
}

# --- the manifest's gate form ------------------------------------------------

_mf() {
    _MF_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nut-mf.XXXXXX")"
    mkdir -p "$_MF_DIR/lib"
    printf 'demo_who() { echo GATED; }\n' > "$_MF_DIR/lib/gated.sh"
    printf 'demo_who() { echo FLOOR; }\n' > "$_MF_DIR/lib/floor.sh"
    printf '%s\n' "$@" > "$_MF_DIR/lib.nut"
}
_mf_done() { rm -rf "$_MF_DIR"; }

#[test]
it_refuses_the_retired_when_column() {
    # `when=` was the earlier gate form and had already stopped being read: the
    # words after the file became the visibility, last one winning, so a row
    # saying `when=shell:nosuchshell` set the visibility to that string, failed
    # to match `internal`, and the module loaded on a machine its predicate
    # excluded. Silently. Refusing is the only honest answer, because ignoring
    # it is what caused that.
    _mf 'demo   lib/gated.sh   when=shell:nosuchshell' 'demo   lib/floor.sh'
    local out; out="$(_lib_nut_lookup "$_MF_DIR" demo 2>&1)"
    local rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "when="
    assert_contains "$out" "#[shell(bash4)]"
    assert_not_contains "$out" "gated.sh
"
    _mf_done
}

#[test]
it_takes_the_first_row_whose_gate_holds() {
    # A gate that cannot hold falls through to the row below, and the row with
    # no gate is the floor.
    _mf '#[shell(nosuchshell)]' 'demo   lib/gated.sh' 'demo   lib/floor.sh'
    assert_contains "$(_lib_nut_lookup "$_MF_DIR" demo 2>/dev/null)" "floor.sh"
    _mf_done

    _mf '#[shell(bash4)]' 'demo   lib/gated.sh' 'demo   lib/floor.sh'
    assert_contains "$(_lib_nut_lookup "$_MF_DIR" demo 2>/dev/null)" "gated.sh"
    _mf_done

    # No gate at all: the first row wins, which is what makes a floor above a
    # better row hide it.
    _mf 'demo   lib/gated.sh' 'demo   lib/floor.sh'
    assert_contains "$(_lib_nut_lookup "$_MF_DIR" demo 2>/dev/null)" "gated.sh"
    _mf_done
}

#[test]
it_accumulates_gates_and_needs_all_of_them() {
    # Attributes attach downward and a run of them all has to hold, the way
    # `#[cfg(...)]` does above a `mod`.
    _mf '#[shell(bash4)]' '#[has(bin(definitely_not_a_binary_xyzzy))]' \
        'demo   lib/gated.sh' 'demo   lib/floor.sh'
    assert_contains "$(_lib_nut_lookup "$_MF_DIR" demo 2>/dev/null)" "floor.sh"
    _mf_done

    _mf '#[shell(bash4)]' '#[has(bin(sh))]' 'demo   lib/gated.sh' 'demo   lib/floor.sh'
    assert_contains "$(_lib_nut_lookup "$_MF_DIR" demo 2>/dev/null)" "gated.sh"
    _mf_done
}

#[test]
it_stops_a_run_of_gates_at_its_own_declaration() {
    # A gate belongs to the next row and not to the one after it. Without that
    # a single `#[shell(...)]` would gate the whole rest of the file, which is
    # the failure nobody would see until a floor row went missing.
    _mf '#[shell(nosuchshell)]' 'other  lib/gated.sh' 'demo   lib/floor.sh'
    assert_contains "$(_lib_nut_lookup "$_MF_DIR" demo 2>/dev/null)" "floor.sh"
    _mf_done
}

#[test]
it_does_not_let_a_plain_comment_carry_a_gate() {
    # A plain `#` line clears the pending run, so prose between a gate and its
    # row breaks the attachment rather than silently keeping it.
    _mf '#[shell(nosuchshell)]' '# just a comment' 'demo   lib/gated.sh' 'demo   lib/floor.sh'
    assert_contains "$(_lib_nut_lookup "$_MF_DIR" demo 2>/dev/null)" "gated.sh"
    _mf_done
}
