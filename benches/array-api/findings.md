# What an indexed array costs without `declare -a`

`benches/maps` answered the associative half. This is the other half and it is
the larger one: counting every construct rather than the first error `dash`
prints, indexed arrays appear in thirteen of the twenty files that cannot yet be
read, against nine for associative arrays.

## The result

One variable per slot, addressed by number. It is the only candidate that stays
usable as the list grows.

| arm | at 400 | at 4000 |
|---|---|---|
| `declare -a` | the baseline | the baseline |
| slots by index | 137% | 170% |
| positional parameters | 462% | 7229% |
| one string, unit-separated | 36650% | over the ceiling |

## Why the two losers lose

**Positional parameters look native and append quadratically.** `set -- "$@" "$x"`
rebuilds the entire list on every append, so a list built one element at a time
costs the square of its length. At four hundred elements that is 4.6x and looks
survivable; at four thousand it is 72x. They also cost the parameters
themselves, so a function using them cannot read its own arguments, and there is
one per scope. Building a list once from a splat is a different operation and is
not what the real uses do.

**A delimited string indexes by scanning.** Appending is a concatenation and
walking is one pass, which are the two things the real uses do most, but
reaching element n means skipping n separators and the scan swamps everything
else.

**Slots need no encoding**, which is why they cost so much less here than the
same technique costs in `benches/maps`. An index is already a legal part of a
variable name, so there is nothing to encode and nothing to fork for. The
associative case pays for turning `lib/some-module.sh:412` into a name; the
indexed case does not.

## The first run of this bench was wrong, and the controls could not catch it

Every arm built its elements through `$(_elem "$i")`, a fork per element. At four
hundred elements that fork was the entire measurement: bash came out at 192ms
where it actually takes 8, slots read as within the noise of bash where they are
137%, and positional parameters read as 118% where they are 462%.

Every arm paid the fork equally, so the agreement control saw agreement and the
spread control saw a steady baseline. Both were working. **A cost every arm
shares is invisible to a control that compares arms**, and the only thing that
catches it is asking what the baseline number should be and noticing it is two
orders of magnitude too large.

The elements are built into a variable now.

## What is not established here

Whether 170% matters anywhere it is paid, which is a question about nutshell's
own hot paths and needs a bench per path.

The growth of the slots arm between the two sizes, 137% to 170%, is real and
unexplained. The shell's symbol table is the obvious suspect and nobody has
looked.

Every number here is single-threaded, on one host, at the sizes stated, under
bash. What any of this costs under a real POSIX shell is a different question.
