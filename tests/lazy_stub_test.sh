#!/usr/bin/env bash
# Tests for the lazy stubs, and for one module meaning one file per unit.
#
# The crash these exist for had no message. A stub loads an implementation and
# then calls the name that implementation was supposed to rebind; when the
# rebind had not happened, that call was the stub calling itself until the
# shell ran out of stack and the process disappeared. Nothing printed, no exit
# status, nothing to read.

use test

ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

# Each of these runs a fresh shell, because the failure is about what one
# process has already loaded.
_run() { bash -c "cd '$ROOT'; . ./init; FUNCNEST=60; $1" 2>&1; }

#[test]
it_survives_a_module_being_sourced_again() {
    local out
    out="$(_run '
        use text
        printf "needle\n" > "$TMPDIR/_ck.$$"
        text_grep needle "$TMPDIR/_ck.$$" >/dev/null
        source lib/text.sh
        text_grep needle "$TMPDIR/_ck.$$" >/dev/null
        printf "SURVIVED"
        rm -f "$TMPDIR/_ck.$$"')"
    assert_ok    grep -q 'SURVIVED' <<<"$out"
    assert_fails grep -q 'nesting level' <<<"$out"
}

#[test]
it_survives_an_implementation_loaded_before_its_owner() {
    local out
    out="$(_run '
        use text::impl::grep_match
        use text
        printf "needle\n" > "$TMPDIR/_ck2.$$"
        text_grep needle "$TMPDIR/_ck2.$$" >/dev/null
        printf "SURVIVED"
        rm -f "$TMPDIR/_ck2.$$"')"
    # The owner installs its stubs over the bindings the implementation made,
    # so the stub has to be able to put them back.
    assert_ok    grep -q 'SURVIVED' <<<"$out"
    assert_fails grep -q 'nesting level' <<<"$out"
}

#[test]
it_still_answers_after_all_that() {
    local out
    out="$(_run '
        use text
        printf "needle\nhaystack\n" > "$TMPDIR/_ck3.$$"
        source lib/text.sh
        text_grep needle "$TMPDIR/_ck3.$$"
        rm -f "$TMPDIR/_ck3.$$"')"
    # Not just "did not crash": it has to still do the thing.
    assert_ok    grep -q 'needle'   <<<"$out"
    assert_fails grep -q 'haystack' <<<"$out"
}

#[test]
it_survives_the_same_for_fs() {
    local out
    out="$(_run '
        use fs
        fs_size ./init >/dev/null
        source lib/fs.sh
        fs_size ./init >/dev/null
        printf "SURVIVED"')"
    assert_ok    grep -q 'SURVIVED' <<<"$out"
    assert_fails grep -q 'nesting level' <<<"$out"
}

#[test]
it_says_something_rather_than_dying_silently() {
    # The guard's own message, when a stub really is on its own. Provoked by
    # putting the stub back with the implementation already loaded and the
    # reload unable to help.
    local out
    out="$(_run '
        use text
        text_grep() { nut_lazy_guard text_grep || return 1; local _NUT_LAZY_text_grep=1; text_grep "$@"; }
        text_grep a b
        printf "EXIT=%s" "$?"')"
    assert_ok grep -q 'did not define' <<<"$out"
    assert_ok grep -q 'EXIT=1'         <<<"$out"
    # A message and a status, rather than a process that disappears.
    assert_fails grep -q 'nesting level' <<<"$out"
}

# --- one name, two units ------------------------------------------------------------

#[test]
it_gives_each_unit_its_own_module_of_the_same_name() {
    local out
    out="$(_run '
        a=$(mktemp -d); b=$(mktemp -d)
        for d in "$a" "$b"; do mkdir -p "$d/lib"; printf "[meta]\nname=\"x\"\n" > "$d/nut.toml"; done
        printf "A_MARK=1\n" > "$a/lib/guard.sh"; printf "guard lib/guard.sh\n" > "$a/lib.nut"
        printf "B_MARK=1\n" > "$b/lib/guard.sh"; printf "guard lib/guard.sh\n" > "$b/lib.nut"
        printf "use super::guard\n" > "$a/mod.sh"
        printf "use super::guard\n" > "$b/mod.sh"
        . "$a/mod.sh"; . "$b/mod.sh"
        printf "A=%s B=%s" "${A_MARK:-unset}" "${B_MARK:-unset}"
        rm -rf "$a" "$b"')"
    # super:: is relative to whoever wrote it. Cached by the name alone, the
    # second unit matched the first unit's entry, loaded nothing, and returned
    # success.
    assert_ok grep -q 'A=1 B=1' <<<"$out"
}

#[test]
it_still_loads_one_file_once_within_a_unit() {
    local out
    out="$(_run '
        a=$(mktemp -d); mkdir -p "$a/lib"
        printf "[meta]\nname=\"x\"\n" > "$a/nut.toml"
        printf "COUNT=\$(( \${COUNT:-0} + 1 ))\n" > "$a/lib/one.sh"
        printf "one lib/one.sh\n" > "$a/lib.nut"
        printf "use super::one\nuse super::one\n" > "$a/mod.sh"
        . "$a/mod.sh"
        printf "COUNT=%s" "$COUNT"
        rm -rf "$a"')"
    assert_ok grep -q 'COUNT=1' <<<"$out"
}

# --- reloading on purpose --------------------------------------------------------------

#[test]
it_loads_again_when_asked_outright() {
    local out
    out="$(_run '
        a=$(mktemp -d); mkdir -p "$a/lib"
        printf "[meta]\nname=\"x\"\n" > "$a/nut.toml"
        printf "COUNT=\$(( \${COUNT:-0} + 1 ))\n" > "$a/lib/one.sh"
        printf "one lib/one.sh\n" > "$a/lib.nut"
        printf "use super::one\nnut_reload super::one\n" > "$a/mod.sh"
        . "$a/mod.sh"
        printf "COUNT=%s" "$COUNT"
        rm -rf "$a"')"
    assert_ok grep -q 'COUNT=2' <<<"$out"
}

#[test]
it_forgets_by_file_rather_than_by_the_name_it_was_asked_about() {
    # Loaded under one name and reloaded under another. Forgetting by the name
    # asked about would forget nothing, `use` would say "already loaded", and
    # the stub that asked for the reload would still be the stub.
    #
    # Written to a file rather than nested inside quotes: the quoting needed to
    # define a function inside a -c inside a test is its own source of bugs.
    local f; f="$(mktemp)"
    cat > "$f" <<'PROBE'
cd "$NUT_ROOT"
. ./init
a=$(mktemp -d); mkdir -p "$a/libs"
printf 'COUNT=$(( ${COUNT:-0} + 1 ))
' > "$a/libs/one.sh"
printf 'one libs/one.sh
' > "$a/lib.nut"
use extern
extern_path() { printf '%s' "$a"; }
use dep::one
nut_reload other::one
printf 'COUNT=%s
' "$COUNT"
rm -rf "$a"
PROBE
    local out; out="$(NUT_ROOT="$ROOT" bash "$f" 2>&1)"
    rm -f "$f"
    assert_ok grep -q 'COUNT=2' <<<"$out"
}
