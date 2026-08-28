# attr-scan: what a POSIX conversion of the attribute reader costs

`attr.sh` is the checker's hot path. Every check that asks whether a function
carries a marker walks the file it lives in and asks two questions of every
line: is this an attribute, and does this define something. Across the library
that is the check, and the inner test is the cost.

## The number

Over 12,388 lines of the library, three passes, seven repeats, best of each:

| arm | best ms | against the first |
|---|---|---|
| bash regex, shipped loop | 3364 | baseline |
| bash regex, new loop | 1738 | 51% |
| posix case, new loop | 1920 | 57% |

Machine: Darwin arm64, bash 5.3.15. Each arm loads exactly one implementation
in a subshell of its own and answers the same questions over the same files.
The old arm comes out of `git show dev:lib/attr.sh` rather than being
reconstructed, so the baseline is what actually shipped.

## What that says, which is not what a two-arm version said

**The POSIX conversion costs about ten percent. The loop restructuring it
forced pays for that nine times over.**

An earlier version of this file had two arms, shipped-regex against
new-case, reported 73%, and concluded that `case` beats a regex once both do
one match per line. That conclusion was wrong and the data never supported it.
Two arms moving two variables cannot say which variable did the work, and the
arm that decides it is the middle row above: the old regexes, in the new loop,
nothing else changed. It is the fastest of the three.

So the honest reading is the reverse of the earlier one. Held at the same loop
shape, the regex is faster than `case` by about ten percent here. What made the
conversion a win anyway is that it forced the loop to be rewritten, and the
loop was where the time was.

## Where the time actually was

Written the obvious way, with a helper per question each taking a raw line, the
conversion measured *slower* than the shipped version. Every helper trimmed its
own leading space and the loop calls two of them per line, so an ordinary line
of prose paid for the trim three times before being recognised as prose.

Trimming once in the loop and handing the result down, plus a `case` on the
first characters to throw out blanks and comments before any of the real work,
is the 1626ms between the first and second rows. None of it required leaving
bash, which is exactly why the third arm had to exist.

## What holds it

The harness refuses a run whose arms disagree, and `answer_of` now refuses a
silent arm as well: two arms that both find nothing agree perfectly, and a
control that passes on that reports a comparison of nothing. All three arms
name the same 417 functions.

`tests/attr_test.sh` drives every function in the module under a POSIX shell
and against bash, and asserts the answers agree and are correct.

## What this does not say

Nothing about a machine that is not this one, and nothing about a file shaped
differently from the library's. The mix of attribute lines, definitions, prose
and blanks is what a real source file has; a file of nothing but attributes
would measure a case the checker never sees.

Nor does it say `case` is slower than a regex in general. It says that for
these six predicates, on this input, in this shell, held at one loop shape, it
was, by about ten percent.
