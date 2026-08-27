# What the shipped map costs, floor against bash

`benches/maps` priced the techniques and said which one to build on. This
prices what got built: both arms drive the shipped surface, `map_new` through
`map_keys`, so the number includes the function boundary, the encoding, and the
insertion order both implementations promise.

Every run leaves a record under `results/` carrying the host and the bash
version, because a millisecond count without them cannot be compared to
anybody else's.

## The result

The floor is roughly twice bash, and the shape of the load moves it.

| load | floor against bash |
|---|---|
| fill-heavy, reading through `map_get` | 208% |
| fill-heavy, reading through `map_read` | 202% |
| read-heavy | 188% |

Read-heavy is cheaper because the encoding is the cost and a read pays it once,
where a set pays it and then maintains the key list.

## Getting there

It started at 360% and three changes took it to 208%, each one an instance of a
finding `benches/maps` had already recorded and the first implementation had
then gone on to violate.

**A fork per unsafe character, 360% to 239%.** The hex lookup returned by
printing, so encoding one key forked once per slash, dot, dash and colon in it.
It returns through a variable now.

**A fork per operation, 239% to 208%.** Every one of `map_set`, `map_get`,
`map_has` and `map_del` called the encoder through a command substitution. The
encoder already left its answer in a variable and the call sites read it now.

**A character-at-a-time scan, folded into the first change.** The encoder walked
one character per iteration. It takes the whole leading run of safe characters
in one expansion instead, so a twenty-two character key is six passes rather
than twenty-two, and a key needing no encoding leaves on the first.

The lesson is not about maps. It is that `benches/maps` already said the
encoding must not fork, in those words, and the implementation written against
that finding forked twice per character anyway. A finding in a document does not
enforce itself.

## `map_read` against `map_get`

`map_get` prints, so a caller reading one value pays a fork. `map_read` leaves
it in a variable of the caller's naming.

On the floor the difference is about 3%, which is small and outside the spreads,
so it is real. On bash the two overlap and nothing is established. Both are
smaller than expected because reads are a fifth of the fill-heavy workload; the
read-heavy case is where the form is worth reaching for.

## What is not established here

**What the floor costs under a real POSIX shell.** Both arms run under bash,
deliberately, so the technique is the variable rather than the shell. `dash`
against `bash` on the same file is a different question and nobody has asked it.

**Whether twice bash matters anywhere it is paid.** That is a question about
nutshell's own hot paths and needs a bench per path.

**What a handle would buy.** The remaining cost is the encoding, and the only
way past it is a caller holding the encoded name rather than the key.
`benches/maps` already prices that ceiling at roughly 1.3x under the name
`slots by index`, so the shape of the answer is known and the API for it is not
built.

Every number here is single-threaded, on one host, at 400 entries.
