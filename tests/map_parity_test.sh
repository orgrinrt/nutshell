#!/usr/bin/env bash
# Tests that the POSIX map answers what the bash one answers.
#
# One is a hash table and the other is a string of encoded variable names, so
# nothing about them looks alike and reading them side by side establishes
# nothing. Both are driven over the same operations and the answers compared,
# the POSIX one under a real POSIX shell rather than under bash: running it
# under bash tests nothing bash does not already cover, and the interesting
# failures are the ones bash forgives.
#
# The keys here are nutshell's own shape, `<path>:<line>`, because that is what
# forced the encoding: `/`, `.`, `-` and `:` cannot appear in a variable name.
#
# `a.b` against `a_b` is the case that matters most. A substitution mapping
# every unsafe character to `_` collides them, and a map whose keys collide is
# worse than no map at all.

use test

ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
POSIXFILE="$ROOT/lib/map.sh"
BASHFILE="$ROOT/lib/map.bash.sh"

_mp_shell() {
    local cand probe; probe="$(mktemp)"
    for cand in dash ash yash posh sh; do
        command -v "$cand" >/dev/null 2>&1 || continue
        printf 'a=(1 2)\n' > "$probe"
        "$cand" -n "$probe" >/dev/null 2>&1 && continue
        printf 'x=1\necho "${x:-}"\n' > "$probe"
        "$cand" -n "$probe" >/dev/null 2>&1 && { rm -f "$probe"; printf '%s' "$cand"; return 0; }
    done
    rm -f "$probe"; return 1
}

# A script run against both files, and its output compared.
_both() {
    local sh="$1" body="$2" b p
    b="$(bash -c 'nut_once() { return 0; }; . "$1" || exit 1; shift; eval "$1"' _ "$BASHFILE" "$body" 2>&1)"
    p="$("$sh" -c 'nut_once() { return 0; }; . "$1" || exit 1; shift; eval "$1"' _ "$POSIXFILE" "$body" 2>&1)"
    assert_eq "$p" "$b" "$body"
}

#[test]
it_has_a_posix_shell_to_compare_under() {
    # The control for every test below. Without it they all skip, and a skip
    # that reports a pass is how a parity suite comes to mean nothing.
    local sh; sh="$(_mp_shell)"
    assert_ne "$sh" ""
    assert_ne "$sh" "bash"
}

#[test]
it_reads_the_floor_under_a_posix_shell_and_the_other_does_not() {
    local sh; sh="$(_mp_shell)" || return 0
    assert_ok "$sh" -n "$POSIXFILE"
    assert_fails "$sh" -n "$BASHFILE"
}

#[test]
it_answers_the_same_for_set_and_get() {
    local sh; sh="$(_mp_shell)" || return 0
    _both "$sh" 'map_new m; map_set m hello world; map_get m hello'
    _both "$sh" 'map_new m; map_set m hello world; map_set m hello again; map_get m hello'
    _both "$sh" 'map_new m; map_get m missing; printf "|%s" "$?"'
    _both "$sh" 'map_new m; map_set m k ""; map_get m k; printf "|empty"'
}

#[test]
it_answers_the_same_for_keys_that_are_not_variable_names() {
    # The whole reason the floor has to encode anything.
    local sh; sh="$(_mp_shell)" || return 0
    _both "$sh" 'map_new m; map_set m "lib/some-module.sh:412" v; map_get m "lib/some-module.sh:412"'
    _both "$sh" 'map_new m; map_set m "a-b" v; map_get m "a-b"'
    _both "$sh" 'map_new m; map_set m "a b" v; map_get m "a b"'
    _both "$sh" 'map_new m; map_set m "a=b,c+d@e" v; map_get m "a=b,c+d@e"'
    _both "$sh" 'map_new m; map_set m "" v; map_get m ""'
}

#[test]
it_does_not_collide_two_keys_that_differ_only_in_punctuation() {
    # `a.b` and `a_b` land on one name under any encoding that maps every
    # unsafe character to `_`. A map whose keys collide is worse than none.
    local sh; sh="$(_mp_shell)" || return 0
    _both "$sh" 'map_new m; map_set m "a.b" one; map_set m "a_b" two; printf "%s|%s" "$(map_get m "a.b")" "$(map_get m "a_b")"'
    _both "$sh" 'map_new m; map_set m "a.b" one; map_set m "a_b" two; map_len m'
    _both "$sh" 'map_new m; map_set m "a/b" one; map_set m "a:b" two; printf "%s|%s" "$(map_get m "a/b")" "$(map_get m "a:b")"'
}

#[test]
it_answers_the_same_for_has_and_an_empty_value() {
    # A key set to nothing is present. Anything reading only the value cannot
    # tell that from absent, which is the distinction `map_has` exists for.
    local sh; sh="$(_mp_shell)" || return 0
    _both "$sh" 'map_new m; map_set m k ""; map_has m k && printf present || printf absent'
    _both "$sh" 'map_new m; map_has m k && printf present || printf absent'
    _both "$sh" 'map_new m; map_set m k v; map_has m k && printf present || printf absent'
}

#[test]
it_answers_the_same_for_len_keys_and_delete() {
    local sh; sh="$(_mp_shell)" || return 0
    _both "$sh" 'map_new m; map_len m'
    _both "$sh" 'map_new m; map_set m a 1; map_set m b 2; map_set m c 3; map_len m'
    _both "$sh" 'map_new m; map_set m a 1; map_set m a 2; map_len m'
    _both "$sh" 'map_new m; map_set m a 1; map_set m b 2; map_set m c 3; map_keys m | tr "\n" " "'
    _both "$sh" 'map_new m; map_set m a 1; map_set m b 2; map_del m a; printf "%s|%s" "$(map_len m)" "$(map_keys m | tr "\n" " ")"'
    _both "$sh" 'map_new m; map_set m a 1; map_del m nope; map_len m'
    _both "$sh" 'map_new m; map_set m a 1; map_del m a; map_has m a && printf present || printf absent'
}

#[test]
it_answers_the_same_after_clearing() {
    local sh; sh="$(_mp_shell)" || return 0
    _both "$sh" 'map_new m; map_set m a 1; map_clear m; printf "%s|%s" "$(map_len m)" "$(map_get m a)"'
    _both "$sh" 'map_new m; map_set m a 1; map_new m; map_len m'
}

#[test]
it_keeps_two_maps_apart() {
    local sh; sh="$(_mp_shell)" || return 0
    _both "$sh" 'map_new one; map_new two; map_set one k a; map_set two k b; printf "%s|%s" "$(map_get one k)" "$(map_get two k)"'
    _both "$sh" 'map_new one; map_new two; map_set one k a; map_clear two; map_get one k'
    _both "$sh" 'map_new one; map_new two; map_set one a 1; map_set two b 2; printf "%s|%s" "$(map_len one)" "$(map_len two)"'
}

#[test]
it_survives_a_value_full_of_the_characters_that_break_things() {
    local sh; sh="$(_mp_shell)" || return 0
    _both "$sh" 'map_new m; map_set m k "a b  c"; map_get m k'
    _both "$sh" 'map_new m; map_set m k "with '"'"'quotes'"'"' and \"more\""; map_get m k'
    _both "$sh" 'map_new m; map_set m k "100% of \$it"; map_get m k'
    _both "$sh" 'map_new m; map_set m k "a*b?c[d]"; map_get m k'
}

#[test]
it_forgets_the_key_as_well_as_the_value_when_cleared() {
    # `map_clear` unset the value and left the presence table, so a cleared map
    # kept a key that `map_get` answered and `map_len` could not count, and
    # `map_set` on that key never re-listed it. `map_new` is `map_clear` plus a
    # line, so reusing a map under its own documented contract corrupted it.
    local sh; sh="$(_mp_shell)" || return 0
    _both "$sh" 'map_new c; map_set c hits 1; map_new c; map_set c hits 2; printf "%s|%s|%s" "$(map_len c)" "$(map_keys c | tr "\n" ",")" "$(map_get c hits)"'
    _both "$sh" 'map_new d; map_set d a 1; map_clear d; map_has d a && printf present || printf absent'
    _both "$sh" 'map_new d; map_set d a 1; map_clear d; map_set d a 2; printf "%s|%s" "$(map_len d)" "$(map_keys d | tr "\n" ",")"'
}

#[test]
it_refuses_a_container_name_that_would_be_code() {
    # Every function puts its first argument into an `eval`, so a name that is
    # not a name is code. A container name is written by the programmer and
    # never taken from data, so refusing is the honest answer and there is
    # nothing to escape.
    local sh; sh="$(_mp_shell)" || return 0
    _both "$sh" 'map_new "m=1; echo PWNED; :" 2>/dev/null; printf "%s" "${m:-clean}"'
    _both "$sh" 'map_new m; map_set "m; echo PWNED" k v 2>/dev/null; printf "%s" "$?"'
    _both "$sh" 'map_new m; map_read "v; echo PWNED" m k 2>/dev/null; printf "%s" "$?"'
    _both "$sh" 'map_new "a-b" 2>/dev/null; printf "%s" "$?"'
    _both "$sh" 'map_new "" 2>/dev/null; printf "%s" "$?"'
    # And a name that is a name still works, or the refusals above would pass
    # against a function that refuses everything.
    _both "$sh" 'map_new ok; map_set ok k v; map_get ok k'
}
