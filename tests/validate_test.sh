#!/usr/bin/env bash
# Tests for validation.
#
# Twenty-six functions were marked as this module's surface with nothing
# exercising any of them, and two were wrong in ways a single negative case
# would have caught.

use validate test

#[test]
it_recognises_an_address_of_eight_groups() {
    assert_ok is_ipv6 "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
    assert_ok is_ipv6 "2001:db8:85a3:0:0:8a2e:370:7334"
}

#[test]
it_recognises_a_compressed_address() {
    assert_ok is_ipv6 "::"
    assert_ok is_ipv6 "::1"
    assert_ok is_ipv6 "2001:db8::1"
    assert_ok is_ipv6 "fe80::"
}

#[test]
it_refuses_a_run_of_colons() {
    # The pattern this replaced allowed a group of zero to four hex digits
    # anywhere, so any run of colons matched: every group between them was
    # allowed to be empty.
    assert_fails is_ipv6 ":::::"
    assert_fails is_ipv6 ":::"
    assert_fails is_ipv6 "::::::::::"
}

#[test]
it_refuses_too_few_groups_without_compression() {
    # An address is eight groups. Without `::` every one has to be written.
    assert_fails is_ipv6 "1:2:3"
    assert_fails is_ipv6 "1:2:3:4:5:6:7"
}

#[test]
it_refuses_more_than_one_compression() {
    # `1::2::3` says nothing about where the zeroes go.
    assert_fails is_ipv6 "1::2::3"
}

#[test]
it_refuses_a_group_that_is_not_hex() {
    assert_fails is_ipv6 "2001:db8::xyz1"
    assert_fails is_ipv6 "2001:db8::12345"
}

#[test]
it_accepts_an_ordinary_hostname() {
    assert_ok is_hostname "example.com"
    assert_ok is_hostname "sub.domain.example.com"
    assert_ok is_hostname "a"
}

#[test]
it_refuses_a_label_over_sixty_three_characters() {
    # The pattern alone accepted a single label of any length, so a
    # 300-character name passed. A name that cannot be resolved is not a
    # hostname whatever it is made of.
    local long
    long="$(printf 'a%.0s' $(seq 64))"
    assert_fails is_hostname "$long"
    assert_fails is_hostname "${long}.com"

    local ok
    ok="$(printf 'a%.0s' $(seq 63))"
    assert_ok is_hostname "$ok"
}

#[test]
it_refuses_a_name_over_two_hundred_and_fifty_three_characters() {
    local long=""
    local i
    for i in $(seq 6); do long+="$(printf 'a%.0s' $(seq 50))."; done
    assert_fails is_hostname "${long}com"
}

#[test]
it_refuses_a_label_on_a_hyphen() {
    assert_fails is_hostname "-example.com"
    assert_fails is_hostname "example-.com"
    assert_fails is_hostname "example..com"
}

#[test]
it_judges_the_ordinary_shapes() {
    assert_ok is_integer "42"
    assert_ok is_integer "-42"
    assert_fails is_integer "4.2"
    assert_fails is_integer "x"

    assert_ok is_positive_integer "1"
    assert_fails is_positive_integer "0"
    assert_fails is_positive_integer "-1"

    assert_ok is_port "80"
    assert_ok is_port "65535"
    assert_fails is_port "65536"
    assert_fails is_port "0"

    assert_ok is_ipv4 "192.168.1.1"
    assert_fails is_ipv4 "256.1.1.1"
    assert_fails is_ipv4 "1.2.3"
}

#[test]
it_reads_truth_and_falsity() {
    assert_ok is_truthy "true"
    assert_ok is_truthy "1"
    assert_ok is_truthy "yes"
    assert_ok is_falsy "false"
    assert_ok is_falsy "0"
    assert_fails is_truthy "false"
}

#[test]
it_knows_set_from_empty() {
    # Both take the name of a variable, not its value.
    filled="x"
    empty=""
    assert_ok is_set filled
    assert_fails is_set empty
    assert_fails is_set never_assigned_anywhere
    assert_ok is_empty empty
    assert_fails is_empty filled
}

#[test]
it_answers_about_a_name_even_when_handed_a_value() {
    # The trap in taking a name. `is_empty "$x"` reads naturally and asks about
    # a variable named after the contents of x, which is almost never set, so
    # the answer is "empty" whatever x holds. Pinned so the shape is at least
    # written down, and so a change to it is a decision rather than a surprise.
    filled="x"
    assert_ok is_empty "$filled"
}

#[test]
it_refuses_a_stray_colon_at_either_end() {
    # Word splitting drops a trailing empty field while the count keeps it, so
    # `1:2:3:4:5:6:7:` came out as eight groups with seven of them checked.
    # Leading colons were already rejected; trailing were not.
    assert_fails is_ipv6 "1:2:3:4:5:6:7:"
    assert_fails is_ipv6 "::1:"
    assert_fails is_ipv6 "1::2:3:"
    assert_fails is_ipv6 ":1:2:3:4:5:6:7"
    assert_fails is_ipv6 "1:2:3:4:5:6:7:8:9"
}

#[test]
it_accepts_the_ipv4_mapped_form() {
    # `::ffff:192.168.1.1` is an address, and the dotted part occupies the last
    # two groups.
    assert_ok is_ipv6 "::ffff:192.168.1.1"
    assert_ok is_ipv6 "::192.168.1.1"
    assert_fails is_ipv6 "::ffff:999.1.1.1"
    assert_fails is_ipv6 "1:2:3:4:5:6:7:192.168.1.1"
}

#[test]
it_refuses_a_zone_identifier() {
    # `fe80::1%eth0` names an address and an interface. The interface is not
    # part of the address, and nothing here is asked to strip it, so the whole
    # string is not one. Pinned so the shape is a decision rather than an
    # accident.
    assert_fails is_ipv6 "fe80::1%eth0"
}

#[test]
it_judges_an_address_by_its_domain() {
    # The pattern this replaced matched `[^@ ]+\.[^@ ]+`, and a dot may sit
    # inside either half of that, so `a@b..c` passed with an empty label in the
    # middle of its domain. The domain is a hostname, judged by the one
    # function that knows what one is.
    assert_ok is_email "a@b.c"
    assert_ok is_email "first.last@example.co.uk"
    assert_fails is_email "a@b..c"
    assert_fails is_email "a@@b.c"
    assert_fails is_email "@b.c"
    assert_fails is_email "a@"
    assert_fails is_email "a@b"
    assert_fails is_email "a b@c.d"
    assert_fails is_email "a@-b.c"
}

# --- the POSIX floor ---------------------------------------------------------

_vt_posix_sh() {
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

# Every case below run under one shell, as a string of ones and zeroes.
#
# One process for the lot rather than one per case, because the interesting
# comparison is between two shells over the same corpus and forking twice per
# case to get it would take longer than the rest of this file put together.
_vt_verdicts() {
    "$1" -c '
        . "$1/lib/validate.sh" >/dev/null 2>&1
        r=""
        while IFS= read -r fn && IFS= read -r arg; do
            if "$fn" "$arg" >/dev/null 2>&1; then r="${r}1"; else r="${r}0"; fi
        done
        printf "%s" "$r"
    ' _ "$NUTSHELL_ROOT" <<'CASES'
is_integer
-42
is_integer
42
is_integer
4x
is_integer

is_integer
-
is_positive_integer
0
is_positive_integer
1
is_non_negative_integer
0
is_port
8080
is_port
0
is_port
65535
is_port
65536
is_ipv4
192.168.1.1
is_ipv4
1.2.3
is_ipv4
1.2.3.4.5
is_ipv4
01.2.3.4
is_ipv4
0.0.0.0
is_ipv4
256.1.1.1
is_ipv4
1.2..3
is_ipv6
::1
is_ipv6
::ffff:192.168.1.1
is_ipv6
1::2::3
is_ipv6
1:2:3:4:5:6:7:
is_email
a@b.c
is_email
a@@b.c
is_email
@b.c
is_email
a@b..c
is_hostname
example.com
is_hostname
-bad.com
is_hostname
bad-.com
is_hostname
a.b.c.d
is_url
https://x.io
is_url
ftp://x.io
is_url
https://
CASES
}

#[test]
# It parses there, which everything below depends on.
it_reads_under_a_posix_shell() {
    local sh; sh="$(_vt_posix_sh)"
    assert_ne "$sh" ""
    assert_ok "$sh" -n "${NUTSHELL_ROOT}/lib/validate.sh"
}

#[test]
# Every validator answers the same under both shells, over the whole corpus.
#
# Driven under a real POSIX shell rather than under bash, because running the
# converted file under bash tests nothing bash was not already covering, and
# the interesting failures are the ones bash forgives. Two of them were found
# exactly this way: the module loaded and defined nothing, because `nut_once`
# does not exist outside bash and the `|| return 0` after it fired; and ten
# glob comparisons had been flattened into string equality, which bash and a
# POSIX shell agree about and which is wrong in both.
it_answers_the_same_under_both_shells() {
    local sh; sh="$(_vt_posix_sh)"
    local p b
    b="$(_vt_verdicts bash)"
    p="$(_vt_verdicts "$sh")"
    assert_ne "$b" ""
    assert_eq "$p" "$b"
}

#[test]
# And the answers are the right ones, not merely agreed on.
#
# The control for the test above, and the one that carries it: two shells
# agreeing on a module that loaded nothing agree perfectly, and a string of
# zeroes reads exactly like a string of correct answers.
it_answers_correctly_under_a_posix_shell() {
    local sh; sh="$(_vt_posix_sh)"
    # Each digit checked against what that validator owes, in the order the
    # cases are written above, rather than pasted from a run:
    #
    #   integer      -42 y, 42 y, 4x n, empty n, bare hyphen n
    #   positive     0 n, 1 y            non-negative  0 y
    #   port         8080 y, 0 n, 65535 y, 65536 n
    #   ipv4         dotted quad y, three parts n, five n, leading zero n,
    #                all zeroes y, 256 n, empty octet n
    #   ipv6         ::1 y, mapped y, double compression n, trailing colon n
    #   email        a@b.c y, two at signs n, empty local n, empty label n
    #   hostname     example.com y, leading hyphen n, trailing hyphen n,
    #                four labels y
    #   url          https y, ftp n, no host n
    assert_eq "$(_vt_verdicts "$sh")" \
        "1100001110101000100110010001001100"
}

#[test]
# Every function in the file, called under a POSIX shell, compared against bash.
#
# The parse check above is not this and cannot be. Three `${val,,}` sat in
# `is_boolean`, `is_truthy` and `is_falsy` through a commit whose subject was
# putting this file on the floor: `dash -n` passed, because a bad substitution
# is fatal when it runs and invisible when it parses. The thirty-four verdict
# cases did run under dash, and covered nine validators, which was the whole
# matrix except the three that were broken.
#
# So the function list is read out of the file rather than written here. A hand
# list is exactly what was already wrong: it named what somebody thought to
# name, and the three it missed were the three that mattered.
#
# `os.sh` has this test already, with a comment saying its first version called
# one function and a `[[` put back into another left it passing. Same shape,
# same lesson, and it took shipping the defect to apply it here.
it_runs_every_function_under_a_posix_shell() {
    local sh; sh="$(_vt_posix_sh)"
    local fns
    fns="$(grep -oE '^[a-z_][a-zA-Z0-9_]*\(\)' "${NUTSHELL_ROOT}/lib/validate.sh" \
           | sed 's/()$//' | sort -u | tr '\n' ' ')"
    assert_ok test "$(printf '%s' "$fns" | wc -w)" -ge 12

    # One benign argument, and the answer is not the point: what is being
    # checked is that the shell got through the body at all. A validator that
    # says no is fine; one that says `Bad substitution` is not.
    # `use` stubbed, exactly as the lowered preamble stubs it. The module says
    # `use log` at file scope and a bare POSIX shell has no resolver, so
    # without this the probe reports `use: not found` and says nothing about
    # the thing it was built to check. A floor consumer is a lowered artifact,
    # where `use` is a stub because everything it would load is already there.
    local probe='
        use() { return 0; }
        . "$1"/lib/validate.sh || exit 1
        for f in $2; do
            printf "%s=" "$f"
            "$f" "x" >/dev/null 2>&1 && printf "1;" || printf "0;"
        done
    '
    local got want
    got="$("$sh" -c "$probe" _ "$NUTSHELL_ROOT" "$fns" 2>&1)"
    assert_not_contains "$got" "Bad substitution"
    assert_not_contains "$got" "not found"
    assert_not_contains "$got" "Illegal"
    assert_ne "$got" ""

    # And it answers the same as bash does. A floor implementation that runs
    # and answers differently is worse than one that does not run.
    want="$(bash -c "$probe" _ "$NUTSHELL_ROOT" "$fns" 2>/dev/null)"
    assert_eq "$got" "$want"
}

#[test]
# The trailing dot, which the conversion changed and nothing held.
#
# The old pattern was anchored at both ends, so a trailing dot failed it. The
# rewrite checks per label and the split yields no final field, so it passes.
# The new answer is the better one, a trailing dot being the fully-qualified
# form, but it is a decision and this is what makes it one.
it_accepts_a_fully_qualified_name_with_its_trailing_dot() {
    assert_ok is_hostname "example.com."
    assert_ok is_hostname "a."
    assert_ok is_email    "user@example.com."
    # And the rest of the dot handling is unchanged, which is the half that
    # says this was a change to one case rather than to the parsing.
    assert_fails is_hostname ".example.com"
    assert_fails is_hostname "a..b"
    assert_fails is_hostname ".."
    assert_fails is_hostname "."
}

#[test]
# A number too large for shell arithmetic is answered, not reported.
#
# `[ "$val" -gt 0 ]` on twenty digits writes `integer expected` to stderr and
# returns 2. A validator's whole job is a quiet yes or no about an input the
# caller could not judge itself, so printing on exactly that input is the one
# thing it must not do. Neither of these reaches arithmetic now.
it_stays_quiet_on_a_number_too_large_to_evaluate() {
    local big="99999999999999999999999999"
    local out rc

    out="$(is_positive_integer "$big" 2>&1)"; rc=$?
    assert_eq "$out" ""
    assert_eq "$rc" "0"

    out="$(is_port "$big" 2>&1)"; rc=$?
    assert_eq "$out" ""
    assert_ne "$rc" "0"
}

#[test]
# A leading zero is not a port, which is a deliberate change.
#
# The old code read it as octal, so `007` was seven and passed while `08080`
# had no valid octal reading and failed with a diagnostic. Neither answer was
# anybody's intent. One rule now, and it is the one `is_ipv4` already applies
# to an octet.
it_refuses_a_port_written_with_a_leading_zero() {
    assert_fails is_port "007"
    assert_fails is_port "08080"
    assert_fails is_port "0"
    assert_ok    is_port "7"
    assert_ok    is_port "8080"
}
