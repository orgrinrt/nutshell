# attr-scan: reading attributes, regex against case

`attr.sh` is the checker's hot path. Every check that asks whether a function
carries a marker walks the file it lives in and asks two questions of every
line: is this an attribute, and does this define something. Across the library
that is the check, and the inner test is the cost.

The question was what moving it off `[[ =~ ]]` costs, because a regex engine is
real work per line and `case` is a glob match with nothing behind it, so the
answer could have gone either way.

## The number

Over 12,377 lines of the library, three passes, seven repeats, best of each:

| arm | best ms | against |
|---|---|---|
| bash regex, as shipped | 3132 | baseline |
| posix case and expansion | 2308 | 73% |

Machine: Darwin arm64, bash 5.3.15. Both arms load exactly one implementation,
in a subshell of its own, and answer the same questions over the same file
list. The old arm comes out of `git show dev:lib/attr.sh` rather than being
reconstructed, so the baseline is what actually shipped.

## The first cut was 35% slower, and why

Written the obvious way, with `_attr_is_attr` and `_attr_defines_set` each
taking a raw line, it measured 4196ms against the regex version's 3108. That is
the honest first result and it was the wrong shape rather than a fact about
`case`.

Every helper trimmed its own leading space, and the loop calls two of them per
line, so an ordinary line of prose paid for the trim three times before being
recognised as prose. Trimming once in the loop and handing the result down,
plus a cheap `case` on the first characters to throw out blanks and comments
before any of the real work, is the whole difference between 4196 and 2308.

So the finding is not that `case` beats a regex. It is that the regex version
was doing one match per line and the first conversion was doing three, and once
both do one, the one without an engine behind it wins.

## What holds it

`tests/attr_test.sh` drives every function in the module under a POSIX shell
and against bash, and asserts the answers agree and are correct. The bench's
own agreement control refuses a run whose arms answer differently, which is
what makes the comparison a comparison.

## What this does not say

Nothing about a machine that is not this one, and nothing about a file shaped
differently from the library's. The mix of attribute lines, definitions, prose
and blanks is what a real source file has; a file of nothing but attributes
would measure a case the checker never sees.
