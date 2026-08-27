#!/usr/bin/env bash
# Tests for `nut-lower`.
#
# The tool exists because `benches/startup` measured what it does: resolving
# `use` ahead of time is noise, and dropping what nothing calls is about 11%.
# So every test here is about the shaking being correct, because a shaker that
# drops something needed is worse than no shaker at all, and this one has been:
# the 3.7x that file used to report was a shaker cutting `_deps_init`.
#
# Four of these are the failure modes that bench found by getting them wrong,
# each of which produced a lowered file that loaded cleanly and answered
# nothing. They are the ones worth keeping.

use test

_LOWER="${NUTSHELL_ROOT}/bin/nut-lower"
_WORK="${NUTSHELL_ROOT}/benches/startup/workload.sh"
_MODS="string,fs,toml,validate,os"

_lower_to() {
    _LOW_OUT="$(mktemp "${TMPDIR:-/tmp}/nut-low.XXXXXX")"
    "$_LOWER" "$_WORK" --use "$_MODS" "$@" -o "$_LOW_OUT" 2>/dev/null
}
_lower_done() { rm -f "${_LOW_OUT:-}"; }

# What the real library answers, computed once.
_real_answer() {
    bash -c '
        . "$1/init" >/dev/null 2>&1 || exit 1
        use string fs toml validate os
        . "$2" >/dev/null 2>&1
        _wl
    ' _ "$NUTSHELL_ROOT" "$_WORK"
}

#[test]
it_answers_what_the_real_library_answers() {
    # The whole test. Everything else here is a reason this one might fail.
    _lower_to
    local want got
    want="$(_real_answer)"
    got="$(bash -c '. "$1" >/dev/null 2>&1; . "$2" >/dev/null 2>&1; _wl' _ "$_LOW_OUT" "$_WORK")"
    assert_ne "$want" ""
    assert_eq "$got" "$want"
    _lower_done
}

#[test]
it_drops_most_of_what_it_loaded() {
    # The point of the exercise. If the shaken file keeps everything, the tool
    # has done the half that measured as noise and skipped the half that pays.
    _lower_to
    local shaken; shaken="$(grep -c '^[a-zA-Z_][a-zA-Z0-9_-]*()' "$_LOW_OUT")"
    _lower_done

    _lower_to --no-shake
    local full; full="$(grep -c '^[a-zA-Z_][a-zA-Z0-9_-]*()' "$_LOW_OUT")"
    _lower_done

    assert_ok test "$shaken" -lt "$full"
    # It measures about 70 of 157. The bound is loose so a new module does not
    # fail this, and it is deliberately not tighter: dropping more would mean
    # dropping something a module calls when it loads, which is what an earlier
    # version of the shaker did and what made it look four times faster than it
    # is. See `benches/startup/findings.md`.
    assert_ok test "$(( shaken * 2 ))" -lt "$(( full * 3 ))"
}

#[test]
it_keeps_working_when_nothing_is_shaken() {
    # `--no-shake` is the concatenation alone, which is the half that measured
    # as noise. It has to stay correct anyway, because the shaking is applied
    # on top of it and a broken base is not visible under a working shaker.
    _lower_to --no-shake
    local want got
    want="$(_real_answer)"
    got="$(bash -c '. "$1" >/dev/null 2>&1; . "$2" >/dev/null 2>&1; _wl' _ "$_LOW_OUT" "$_WORK")"
    assert_eq "$got" "$want"
    _lower_done
}

#[test]
it_strips_the_per_file_inclusion_guards() {
    # `nut_once` answers about the file being sourced, and concatenated every
    # file is the same file: the first call registers the lowered one and every
    # guard after it says already-loaded and returns from the whole thing. Left
    # in, the result defines one module and nothing else.
    _lower_to --no-shake
    assert_eq "$(grep -c '^nut_once || return' "$_LOW_OUT")" "0"
    assert_eq "$(grep -c '^\[ -n "\${_NUTSHELL_[A-Z_]*:-}" \] && return 0' "$_LOW_OUT")" "0"
    # And it did define more than one module's worth.
    assert_ok test "$(grep -c '^[a-zA-Z_][a-zA-Z0-9_-]*()' "$_LOW_OUT")" -gt 100
    _lower_done
}

#[test]
it_rewrites_super_away() {
    # `super::` resolves relative to the file that wrote the call, through
    # `BASH_SOURCE[1]`, and concatenated every call comes from the lowered
    # file. Wherever that lands the relative name means something else, and in
    # a temp directory with no manifest above it, nothing.
    _lower_to --no-shake
    assert_eq "$(grep -c 'super::' "$_LOW_OUT")" "0"
    _lower_done
}

#[test]
# Where the dispatch is left to run, the file registers what it contains rather
# than stubbing the resolver.
#
# `use() { return 0; }` looks equivalent and is not, **on this path**:
# `nut_reload` goes through `use`, so a stub breaks the lazy dispatch and the
# dispatched function answers nothing.
#
# It became conditional when pre-binding landed. With the implementation bound
# ahead of the first call the stub never runs, `nut_reload` is never reached,
# and the stub is then correct and is what lets the file drop `init` entirely.
# So the rule this test guards is now the `--no-prebind` rule, and the test says
# so rather than asserting it of every lowering.
it_registers_what_it_contains_when_the_dispatch_is_left_to_run() {
    _lower_to --no-shake --no-prebind
    assert_contains "$(cat "$_LOW_OUT")" '_NUTSHELL_LOADED['
    assert_not_contains "$(cat "$_LOW_OUT")" 'use() { return 0; }'
    # Every registration before any body, or anything reading up to the first
    # module marker sees only one of them.
    local firstreg firstmod
    firstreg="$(grep -n '_NUTSHELL_LOADED\[' "$_LOW_OUT" | tail -1 | cut -d: -f1)"
    firstmod="$(grep -n '^# --- ' "$_LOW_OUT" | head -1 | cut -d: -f1)"
    assert_ok test "$firstreg" -lt "$firstmod"
    _lower_done
}

#[test]
it_follows_nut_reload_into_the_closure() {
    # A module reached only by the lazy dispatch is as much a dependency as one
    # reached by `use`. Following only `use` leaves the implementation out, and
    # `fs_size` then answers nothing.
    local listed; listed="$("$_LOWER" "$_WORK" --use "$_MODS" --list 2>/dev/null)"
    assert_contains "$listed" "fs/impl/"
    # All three, because which one is right depends on the machine and a
    # lowering that kept only the local one would not run elsewhere.
    assert_eq "$(printf '%s\n' "$listed" | grep -c 'fs/impl/')" "3"
}

#[test]
it_orders_a_dependency_before_what_needs_it() {
    # Concatenated, load order is file order. A module whose dependency comes
    # after it runs its file-scope code against functions that do not exist.
    local listed; listed="$("$_LOWER" "$_WORK" --use "$_MODS" --list 2>/dev/null)"
    local deps_at fs_at
    deps_at="$(printf '%s\n' "$listed" | grep -n 'lib/deps.sh' | cut -d: -f1)"
    fs_at="$(printf '%s\n' "$listed" | grep -n 'lib/fs.sh' | cut -d: -f1)"
    assert_ne "$deps_at" ""
    assert_ne "$fs_at" ""
    assert_ok test "$deps_at" -lt "$fs_at"
}

#[test]
it_keeps_file_scope_code_that_is_not_a_definition() {
    # Shaking cuts function definitions and nothing else. Rebuilt from
    # `declare -f` instead, the result is functions only and every module's
    # load-time initialisation goes: `deps.sh` populating its tool table is the
    # one that shows, and the dispatched functions then read an empty table.
    _lower_to
    assert_contains "$(cat "$_LOW_OUT")" '_TOOL_CAN_NAMES'
    # And the table is actually populated when it loads, which is the thing
    # the initialisation does.
    local n; n="$(bash -c '. "$1" >/dev/null 2>&1; printf "%s" "$_TOOLS_AVAILABLE" | wc -w' _ "$_LOW_OUT")"
    assert_ok test "$n" -gt 0
    _lower_done
}

#[test]
it_refuses_a_script_that_names_no_modules() {
    local out rc
    out="$("$_LOWER" "$_WORK" 2>&1)"; rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "loads no modules"
}

#[test]
# Every module named to `--use` reaches the closure, including the last one.
#
# It did not. The list is split with `printf '%s' | tr ',' '\n'`, which writes
# no trailing newline, so `read` returned non-zero on the final field and the
# loop exited without walking it. `--use text,fs` lowered `text` and left `fs`
# out, and nothing failed: the lowered file loaded, and answered nothing for
# half of what was asked for.
#
# Asserted by comparing counts rather than by naming files, because which
# modules a module pulls in is its own business and changes.
it_walks_every_module_named_to_use() {
    local one two both
    one="$("$_LOWER" "$_WORK" --use text --list 2>/dev/null | wc -l)"
    two="$("$_LOWER" "$_WORK" --use fs --list 2>/dev/null | wc -l)"
    both="$("$_LOWER" "$_WORK" --use text,fs --list 2>/dev/null | wc -l)"

    # Each alone has to reach something at all. One module returning the
    # one-line "loads no modules" error is exactly the bug, and it counts as 1.
    assert_ok test "$one" -gt 1
    assert_ok test "$two" -gt 1

    # Together they reach more than either alone. With the last one dropped,
    # `text,fs` equalled `text` exactly.
    assert_ok test "$both" -gt "$one"
    assert_ok test "$both" -gt "$two"
}

#[test]
# The single-module case, which is the one the bug hit hardest: with one name
# and no comma, the only field is the last field, so nothing was walked at all
# and the tool reported the entry loading no modules.
it_lowers_a_single_named_module() {
    local out; out="$("$_LOWER" "$_WORK" --use text --list 2>&1)"
    assert_not_contains "$out" "loads no modules"
    assert_contains "$out" "lib/text.sh"
}

#[test]
# A dispatched function answers without the dispatch running.
#
# This is what "resolved ahead of time" has to mean. The lowering knows which
# implementation `deps_has` would pick, so the lowered file carries that
# implementation bound to the name already, and the first call is the real
# function rather than a stub that goes and loads one.
#
# `nut_reload` is made a canary. If the dispatch still runs it fires, and the
# test says so, which is stronger than timing: it fails on the mechanism being
# present rather than on it being slow.
it_binds_the_implementation_ahead_of_the_first_call() {
    _LOW_OUT="$(mktemp "${TMPDIR:-/tmp}/nut-low.XXXXXX")"
    "$_LOWER" "$_WORK" --use text --no-shake -o "$_LOW_OUT" 2>/dev/null

    local out
    out="$(bash -c '
        . "$1" >/dev/null 2>&1 || exit 1
        nut_reload() { printf "DISPATCH-RAN\n"; return 0; }
        f="$(mktemp)"; printf "alpha\n" > "$f"
        text_contains alpha "$f" && printf "yes\n" || printf "no\n"
        rm -f "$f"
    ' _ "$_LOW_OUT" 2>&1)"

    assert_not_contains "$out" "DISPATCH-RAN"
    assert_contains "$out" "yes"
    _lower_done
}

#[test]
# The control, and the reason the test above is not vacuous.
#
# Without pre-binding the same probe must see the dispatch run. If it does not,
# the canary is not wired to anything and the test above proves nothing.
it_still_dispatches_at_first_call_without_prebinding() {
    _LOW_OUT="$(mktemp "${TMPDIR:-/tmp}/nut-low.XXXXXX")"
    "$_LOWER" "$_WORK" --use text --no-shake --no-prebind -o "$_LOW_OUT" 2>/dev/null

    local out
    out="$(bash -c '
        . "$1" >/dev/null 2>&1 || exit 1
        nut_reload() { printf "DISPATCH-RAN\n"; return 0; }
        f="$(mktemp)"; printf "alpha\n" > "$f"
        # Not redirected. `>/dev/null` here swallows the canary too, which
        # made this control pass for the wrong reason the first time.
        text_contains alpha "$f"
        rm -f "$f"
    ' _ "$_LOW_OUT" 2>&1)"

    assert_contains "$out" "DISPATCH-RAN"
    _lower_done
}

# A POSIX shell that is one, or nothing.
_nl_posix_sh() {
    local cand f; f="$(mktemp)"; printf 'declare -A x\n' > "$f"
    for cand in dash ash yash busybox-sh; do
        command -v "$cand" >/dev/null 2>&1 || continue
        "$cand" -c ". '$f'" >/dev/null 2>&1 || { rm -f "$f"; printf '%s' "$cand"; return 0; }
    done
    rm -f "$f"; return 1
}

#[test]
# A lowered file runs under a POSIX shell, which is the point of the floor.
#
# It did not, and no amount of converting modules would have changed that: the
# emitted preamble sourced `init`, and `init` opens with `declare -gA`, which is
# the first thing a POSIX shell refuses. Every module underneath could have been
# perfectly POSIX and none of it was reachable.
#
# `init` is the development-time resolver. Six of its functions answer "which
# file is this module" out of `lib.nut` and four more make a module load once,
# and a lowered file has had both done to it already. What it actually
# referenced was `use` at file scope, `nut_reload` and `nut_lazy_guard` inside
# stubs that pre-binding overwrites, and one `NUTSHELL_ROOT`.
#
# `os` is lowered here rather than a larger closure because it carries no
# `#[shell(bash4)]` gate. A gate resolves against the shell doing the lowering,
# so lowering `string` under bash correctly picks the bash half and the artifact
# is then a bash artifact by construction.
it_produces_a_file_a_posix_shell_can_run() {
    local sh; sh="$(_nl_posix_sh)" || { skip "no strict POSIX shell here"; return 0; }
    _LOW_OUT="$(mktemp "${TMPDIR:-/tmp}/nut-low.XXXXXX")"
    "$_LOWER" "$_WORK" --use os --no-shake -o "$_LOW_OUT" 2>/dev/null

    # No `init`, and none of the tables that need an associative array.
    assert_fails grep -q '/init"' "$_LOW_OUT"
    assert_fails grep -q '_NUTSHELL_LOADED\[' "$_LOW_OUT"

    assert_ok "$sh" -n "$_LOW_OUT"

    local got
    got="$("$sh" -c '. "$1" && os_name' _ "$_LOW_OUT" 2>&1)"
    assert_not_contains "$got" "not found"
    assert_not_contains "$got" "Syntax error"
    assert_eq "$got" "$(bash -c '. "$1" && os_name' _ "$_LOW_OUT" 2>&1)"
    _lower_done
}

#[test]
# The control, and the reason the preamble is chosen on pre-binding.
#
# Without it a stub still runs and still calls `nut_reload`. A no-op there would
# leave it calling itself until `nut_lazy_guard` stopped it, so the function
# would answer nothing at all. `--no-prebind` therefore keeps the old preamble
# and stays a bash artifact, and this asserts that rather than leaving it to a
# comment.
it_keeps_the_bash_preamble_when_the_dispatch_is_left_to_run() {
    _LOW_OUT="$(mktemp "${TMPDIR:-/tmp}/nut-low.XXXXXX")"
    "$_LOWER" "$_WORK" --use os --no-shake --no-prebind -o "$_LOW_OUT" 2>/dev/null

    assert_ok grep -q '/init"' "$_LOW_OUT"
    assert_contains "$(head -1 "$_LOW_OUT")" "bash"

    # And it still works under bash, which is what it is for.
    assert_eq "$(bash -c '. "$1" && os_name' _ "$_LOW_OUT" 2>&1)" "$(bash -c 'uname -s' | tr 'A-Z' 'a-z' | sed 's/darwin/macos/')"
    _lower_done
}
