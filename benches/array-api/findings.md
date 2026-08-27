# What an indexed array costs without `declare -a`

`benches/maps` answered the associative half. This is the other half and it is
the larger one: counting every construct rather than the first error `dash`
prints, indexed arrays appear in thirteen of the twenty files that cannot yet be
read, against nine for associative arrays.

## The result

**Keep the list as a string and let the shell split it.** `IFS` set to the
separator and `set -- $s`, or `for e in $s`, is field splitting, which the shell
does in C to every unquoted expansion anyway.

At 400 elements and at 4000, against bash's own `declare -a`:

| arm | 400, indexed | 4000, indexed | 400, walked | 4000, walked |
|---|---|---|---|---|
| `declare -a` | the baseline | the baseline | the baseline | the baseline |
| string, split by the shell | within the noise | 117% | within the noise | within the noise |
| string, split then shifted | 122% | 126% | within the noise | 116% |
| slots by index | 144% | 153% | 137% | 158% |
| positional parameters | 433% | 5420% | | |
| rope, chunked strings | 1300% | 1076% | | |
| string then split on index | 1244% | 16171% | | |
| one string, scanned | 32622% | over the ceiling | 725% | 9261% |

Two tables because indexing and walking want opposite things and one table
mixing them hides that. Most of the real uses never index at all: `_BENCH_LABEL`,
`seen`, the toml accumulators are all appended to and then walked once.

## Why the shell splitting wins

Every other string arm splits in a shell loop, one parameter expansion per
element, and every one of them loses by orders of magnitude. `${rest#*sep}`
copies the whole remainder each time, so a walk is quadratic in the length of
the list and an index is quadratic again on top.

The shell already has that loop written in C. Handing it the string and letting
it do what it does to every unquoted expansion costs one pass.

**It needs two lines and both are easy to leave out.** `set -f`, because field
splitting is followed by pathname expansion and an element holding `*` would
otherwise become a directory listing. And `IFS` set to the separator alone, or
every space and newline inside an element splits it further.

**Walking needs no positional parameters at all.** `for e in $s` field-splits
exactly as `set -- $s` does and never touches `$@`, so the one-list-per-scope
objection applies only to indexing. That is the cheaper half of the problem and
the rarer one.

## The first answer was wrong, and it was wrong by being narrow

This bench first carried four arms and concluded that slots by index, one shell
variable per element addressed through `eval`, was the answer at 137% and 170%.
That number was right and the conclusion was not: the string family had been
represented by its worst member, a single string scanned in a shell loop, which
lost by four orders of magnitude and took the whole family down with it.

Widening it to seventeen arms across four families put the same string family at
the top, at 117%, beating slots at both sizes.

The lesson is about the shape of the comparison rather than about arrays. **One
bad member is enough to retire a family**, and the arms that got added later
were not more clever than the ones that were there, they were the same family
done properly.

## What else the arms settled

**Batching the `eval` calls makes it worse**, 188% against 144%. The diagnostic
arm beside it does one extra `eval` per append and costs 155%, so a whole `eval`
is about 8% and there was never enough there to win. What batching adds is
quoting the value into the program text, and that costs more than the call it
saves.

**`declare -a`'s `+=` is not a special fast path.** Appending and assigning by
index measure identically at both sizes.

**Positional parameters append quadratically.** `set -- "$@" "$x"` rebuilds the
whole list every time: 433% at four hundred elements, 5420% at four thousand.
They look native and they are the wrong native thing. Splitting into them once is
the right one.

**A rope is slots with extra steps.** Chunking the string bounds the scan to the
chunk size, and its limit as the chunk approaches one element is exactly slots,
which it never beats.

**Splitting lazily on first index is the worst arm here**, 16171% at four
thousand, because the conversion is the same quadratic shell loop and it runs
inside the timed region.

## The first run of this bench was wrong in a way no control could catch

Every arm built its elements through `$(_elem "$i")`, a fork per element. At four
hundred elements that fork was the entire measurement: bash came out at 192ms
where it actually takes 8, slots read as within the noise of bash where they are
137%, and positional parameters read as 118% where they are 433%.

Every arm paid it equally, so the agreement control saw agreement and the spread
control saw a steady baseline. Both were working. **A cost every arm shares is
invisible to a control that compares arms**, and the only thing that caught it
was asking what the baseline number should be and noticing it was two orders of
magnitude too large.

## What is not established here

**Whether the ceremony is affordable at the call site.** A function's `set --` is
local to that function, so nothing can split on the caller's behalf: the caller
writes `set -f; IFS=...; set -- $l` itself. That is three lines per use, which is
either unacceptable or exactly what lowering is for, and this bench does not say
which.

**Elements cannot contain the separator.** `\037` is not a character nutshell's
own lists carry, and that is an observation rather than a guarantee. Encoding it
on push costs a `case` test per element, which is unmeasured.

**The growth of the slots arm between sizes**, 144% to 153%, is real and
unexplained. The shell's symbol table is the obvious suspect and nobody looked,
which matters less now that slots are not the answer.

Every number is single-threaded, on one host, under bash, at the sizes stated.
What any of it costs under a real POSIX shell is a different question.
