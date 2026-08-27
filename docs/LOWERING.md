# Lowering, and where the branching belongs

Op's shape, recorded before it is built.

## The manifest carries the gates, attribute-shaped

Module gating goes in `lib.nut`, on the declaration, the way Rust gates a top
level module: the attribute sits where the module is declared, and it resolves
either to an equally named module tree or to the module not being there at all.

```
#[has(bin(grep))]
text                     lib/text.fast.sh
text                     lib/text.sh
```

The `when=` column is retired in favour of this. Two spellings for one idea was
an extra layer, and the attribute form is the one the rest of the library
already speaks.

## Why the shell gate cannot move into the file

This is the constraint that decides the shape, and it is worth stating plainly
because the obvious answer is wrong.

A tool predicate can live inline. `#[has(bin(grep))]` on a function picks an
implementation, the file parses either way, and nothing is at risk.

A shell predicate cannot. The file it gates contains `[[ ]]` or `declare -A`,
and a POSIX shell rejects the whole file at parse time, before running a line
of it. An attribute inside that file is inside the thing that fails to parse.
So the shell gate has to sit where the module is declared, outside the file it
is about, and `lib.nut` is that place.

## `bin(...)` rather than a bare argument

`#[has(grep)]` reads well and has to guess what kind of thing `grep` is. The
predicate already distinguishes three: a binary on `PATH`, an environment
variable, and the running shell. The inner form says which without ambiguity
and extends when a fourth appears.

## What the measurements say so far

**Resolving `use` at lower time does not pay.** Both arms loading the same
surface, `benches/startup`:

| modules | resolved | lowered | |
|---|---|---|---|
| 1 | 19 ms | 16 ms | within the noise |
| 5 | 224 ms | 197 ms | within the noise |

The cost is parsing the files, not finding them. An earlier run of this bench
reported 217 ms against 15 ms and was wrong: the lowered arm stubbed `use` and
never loaded the dependencies, so it was doing less work rather than doing it
faster. The harness refuses that shape now, because `bench_verify` compares the
whole loaded surface rather than one function's output.

**Two things are not yet measured and are where the win would be.**

Dropping what nobody calls. Of the 76 functions the truncated arm was missing,
71 were referenced by nothing, so a lowering that keeps only what is reachable
would parse far less. That is the candidate worth pricing next.

Resolving the lazy dispatch. `nut_lazy_guard`, `nut_reload` and `deps_has` are
the machinery that picks an implementation at first call, and a lowering knows
the answer already: it can emit the chosen impl directly and delete the guard.
Those same names are what broke the ten-module run of this bench, which is the
problem showing itself rather than a bench defect.

## What lowering has to do that is not obvious

Strip the per-file inclusion guards. `nut_once` answers about the file being
sourced, and concatenated every file is the same file: the first call registers
it and every guard after says "already loaded" and returns from the whole
thing. Found by the lowered arm defining one module and nothing else.

## Visibility is the same pass

Not a second mechanism. The rungs decide the retained set: `#[pub]` from
anywhere, `#[pub(lib)]` from inside the library, `#[pub(super)]` from the
parent module, and anything unmarked from its own module only. What is not
retained is not in the emitted file, which is real unreachability rather than a
naming convention.

Anything not marked `#[pub]` is private. That is the rule, and it is not the
leading-underscore convention: 19 functions carry no marker and no underscore
today, and they read as api.

`#[pub(lib)]` already works end to end and nothing uses it. `attr` parses the
argument, `modgraph`'s scanner records it, and the audit has the rung.
`#[pub(super)]` parses and records but the audit treats it as private, because
nothing yet knows that `super` means the parent in the `::` path.

## Where enforcement is today

The gate catches a private cross-module call, including unmarked and
underscore-prefixed ones. Runtime catches nothing: `use attr` hands you
`_attr_name` and it runs, because sourcing fills one namespace.
