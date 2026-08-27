# What a lowered form would save at load time

**Not established. The first measurement was not sound and is recorded here so
nobody quotes it.**

## The unsound run

    resolved through the manifest    217 ms
    lowered, one file                 15 ms
    a bare shell, loading nothing     12 ms

Read as written that is the load cost falling from 205 ms to 3 ms. It is not,
because the two arms did not load the same thing: the resolved arm defined 165
functions and the lowered arm 90.

The lowered arm concatenates the modules named on the command line and stubs
`use` to a no-op, so a module reaching for its own dependencies at load time
gets nothing. The resolved arm loads those dependencies for real. So part of
the gap is the lowered arm doing less work rather than doing it faster.

The direction is almost certainly right. Every `use` resolves through
`_lib_nut_lookup`, every caller of that wraps it in a command substitution, and
a fork is not cheap. But the size of it is unmeasured.

## What a sound version needs

The arms have to load the same set. Two ways, and the second is better:

- Expand the module list to the transitive closure before concatenating, so
  both arms end with the same functions defined. Straightforward and still
  hand-rolled.
- Have the lowering resolve `use` itself rather than stubbing it, which is what
  a real lowering does anyway. Then the arms are the same program by
  construction and the bench prices the thing rather than a sketch of it.

Either way the harness will refuse a run whose arms disagree once they are
asked the right question, which is `bench_verify` over the loaded surface
rather than over one function's output. The current verify calls `str_upper`,
which both arms answer identically while differing by 75 functions.

## What is not in question

That the resolved path forks per module. That is structural: `_lib_nut_lookup`
prints its answer and all five call sites capture it with `$( )`.
`benches/module-resolve` prices a predicated row against a plain one and names
this as the larger cost sitting underneath both.
