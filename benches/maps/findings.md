# What a map costs without bash associative arrays

The question behind it: nutshell is to be POSIX sh by default, and POSIX sh has
no associative arrays. nutshell uses them where they decide how fast it is, so
the substitute has a price and this is the price.

The numbers below are from this machine, at 9606 entries, which is the size of
the largest real table here: `_PAD_LINES` in the docs check holds one entry per
line of source. Every run leaves a record under `results/`, and those carry the
host and the bash version, because a millisecond count without them cannot be
compared to anybody else's.

## The result

The substitute is about three times bash, and about a third more where the
caller can hold a handle rather than a key.

| arm | against bash |
|---|---|
| `declare -A` | the baseline |
| eval names, encoded in place | roughly 3x |
| slots by index, holding a handle | roughly 1.3x |
| eval names, encoded through a subshell | far worse, and the gap is the fork |
| one file per key | worse again |
| hash table rolled by hand | tens of times worse |
| one string, scanned | thousands of times worse |

## What to take from it

**The encoding must not fork.** Two arms here are the same technique, one
calling out to encode a key and one doing it in place. The gap between them is
larger than the gap between the technique and bash, so the habit costs more than
the substitution does.

**Never roll a hash table in the shell.** The shell's own symbol table hashes in
C and a shell loop cannot compete with it. That arm is here because somebody
will suggest it.

**Two arms are not maps.** `slots by index` and `slots by stride` are what a map
becomes once the key has been resolved and the caller holds the index. They are
here to price the key lookup, which is what a design would be trading away, and
not as alternatives to `declare -A`.

## What is not established here

Whether the 3x matters anywhere it is paid. That is a question about nutshell's
own hot paths rather than about maps, and answering it needs a bench per path
rather than this one.

And every number here is single-threaded, on one host, at the sizes the table
states. Nothing here says what happens on a smaller machine, which is where the
POSIX floor matters most.
