#!/usr/bin/env bash
# Tests for the key encoder.
#
# It was `_deps_key`, private to `deps.sh`, and these tests came with it. They
# are here rather than there because the thing they test is not about tools:
# `use` keys its loaded table the same way, and a test suite that lives beside
# one caller stops being run when the other one changes.

use test key

#[test]
# Every character the hex table names, against what that character actually is.
#
# The table is fifty-odd arms written by hand, so a typo in one of them is the
# real risk and it would be silent: a wrong hex digit still produces a valid
# variable name, so the tool resolves to the wrong entry or to nothing, and
# nothing anywhere says a byte was mis-encoded.
#
# So the expectation is computed rather than written down. `printf '%d' "'c"`
# is the same answer from a different mechanism, which is the point: a table
# checked against a copy of itself checks nothing.
it_encodes_every_character_as_that_character() {
    local c n want
    for c in a b c d e f g h i j k l m n o p q r s t u v w x y z \
             A B C D E F G H I J K L M N O P Q R S T U V W X Y Z \
             0 1 2 3 4 5 6 7 8 9 - . + '~' _; do
        _nut_hex "$c"
        n="$(printf '%d' "'$c")"
        want="$(printf '%02x' "$n")"
        assert_eq "$_nh" "$want" "the table says $c is $_nh and it is $want"
    done
}

#[test]
# The fallback still works, for a byte the table does not name.
#
# The table exists to keep the common path out of a subshell, not to replace
# the general answer. A character outside it has to keep encoding correctly or
# the one-to-one property the whole scheme rests on stops holding.
it_still_encodes_a_character_the_table_does_not_name() {
    local c
    for c in '%' '@' '!' ':'; do
        _nut_hex "$c"
        assert_eq "$_nh" "$(printf '%02x' "$(printf '%d' "'$c")")"
    done
}

#[test]
# Keying a hyphenated name reaches no subshell.
#
# It reached eighteen: two nested command substitutions per character, and
# every letter took that arm because only the digits and four punctuation marks
# were named. `deps_has` takes this path for every tool whose name is not
# already a variable name, which is most of the interesting ones.
#
# Asserted as a time rather than a fork count, because a shell cannot count its
# own forks. The bound is loose on purpose: eighteen subshells measured about
# 8.8ms per key and the table about 0.4ms, so anything under 3ms says the forks
# are gone without the test failing on a slow machine.
it_keys_a_hyphenated_name_without_forking_per_character() {
    local t0 t1 per
    t0="$(date +%s%N 2>/dev/null)" || { skip "no nanosecond clock"; return 0; }
    local i=0
    while [ "$i" -lt 100 ]; do nut_key pkg-config; i=$((i+1)); done
    t1="$(date +%s%N)"
    per=$(( (t1 - t0) / 100 / 1000 ))
    assert_eq "$_nk" "enc_706b672d636f6e666967"
    assert_ok test "$per" -lt 3000
}
