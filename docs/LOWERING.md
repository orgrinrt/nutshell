# Lowering, and where the branching belongs

Op's shape, recorded before it is built.

Everything here is settled. The sections that were drafted awaiting a ruling
have had one, and where a ruling went against the draft the draft is gone
rather than kept beside it.

## The manifest carries the gates, attribute-shaped

Module gating goes in `lib.nut`, on the declaration, the way Rust gates a top
level module: the attribute sits where the module is declared, and it resolves
either to an equally named module tree or to the module not being there at all.

```
#[has(bin(grep))]
text                     lib/text.fast.sh
text                     lib/text.sh
```

Built. The `when=` column is gone.

`#` already means comment in this format, so a reader that knows nothing about
gates skips them and the file stays what it was. That is the same trick `attr`
uses for `#[pub]` in a shell file, and it is why the shape is a comment rather
than a new column.

Gates attach downward and accumulate, the way several `#[cfg]` lines do above
one `mod`. Every one in a run has to hold. A gate stops at the declaration it
applies to; carried past it, one false gate near the top would hide every row
under it.

The vocabulary is four attributes and nothing else:

    shell(bash)      the running shell is bash, any version
    shell(bash4)     bash 4 or newer
    has(bin(grep))   that command is on PATH
    has(env(NAME))   that variable is set and not empty

An unknown one does not hold, and `nut-declare --check` reports it, because a
gate the resolver refuses is a variant that silently never loads.

## Features are a choice; a gate is an observation

**Op's ask, and the three questions this section used to leave open are
answered below.**

`nut.toml` grows a `[features]` table, the way `Cargo.toml` has one:

```toml
[features]
default = ["bash"]
bash    = []
```

and `lib.nut` gains a fifth attribute that reads one:

```
#[feature(bash)]
map                      lib/map.bash.sh
map                      lib/map.sh
```

The lowering selects them the way cargo does, with `--features` and
`--no-default-features`, and the selection is what decides which row wins.
`NUT_FEATURES` and `NUT_NO_DEFAULT_FEATURES` are the same two through the
environment, which is how the lowering passes them down.

The set is worked out on the first gate that asks, never while `init` is
sourced. That laziness is load-bearing: a tool sources `init`, parses its own
flags and exports the two variables, and the export counts because nothing has
read the set yet.

### Why this is not the shell gate again

The four attributes above are all **predicates over the machine**. They ask what
this computer has: which shell is running, whether a binary is on `PATH`,
whether a variable is set. They are observations, they are answered where they
are asked, and that is right for a program deciding at load time what it can do
here.

A lowering is not deciding what it can do here. It is deciding what to write
into a file that will run somewhere else, and an observation cannot answer
that. The case that settles it is CI: a build host bakes bundles for several
targets, and every one of those targets is a machine it is not.

The case that showed it: lowering `string` on this machine takes
`lib/string.sh`, the bash half, because `#[shell(bash4)]` asks the running shell
and the running shell is bash. Nothing is wrong with that answer. It is what the
gate means. But it makes a POSIX artifact impossible to produce from a machine
that has bash, which is every machine anybody lowers on, and the emitted file
then carries a `local -n` nameref that a POSIX shell refuses. The floor is
reachable in principle and unreachable in practice, and no amount of converting
modules changes it.

So a feature is chosen by the person doing the lowering, and a gate is what
the manifest writes down about a variant. Both stay, and they are different
things: one is the question, the other is the answer chosen for a target.

### A feature always wins, and every gate resolves at lower time

Every attribute is settled while lowering, and the arms not taken are lowered
out. Nothing about a gate survives into the artifact, `has(bin(...))` included.

This follows from what a lowering is for. A build host bakes a bundle for a
target it is not, so an observation of the build host is the wrong answer to
every question, not only to the shell one. A tool gate reads as though it could
stay live, because a binary can be looked for at run time and a shell cannot be
re-parsed; but the artifact is being written for another machine either way,
and a test that runs there answers about a machine nobody was building for.

So a feature is never overridden by a gate. Selecting one would otherwise mean
nothing, which is the whole reason features exist.

A host that has a tool and wants a bundle built without it says so the same
way as everything else, by selecting features: `--features foo,bar,baz`. The
opt-out is a selection rather than a second mechanism.

### The cargo rules that carry over

**Additive.** Enabling a feature only ever adds. A feature that removes
something breaks every consumer that enabled it for an unrelated reason, which
is the rule cargo learned the hard way and there is no reason to relearn it.

**`default` is a set like any other**, and `--no-default-features` drops it.
Nothing else about a feature is special.

**A row without a `#[feature(...)]` is always in.** Gating is opt-in, so a
manifest that declares no features behaves exactly as it does today.

**A feature reaches a whole tree, not only a row.** Cargo's shape carries over
in full: a feature may enable a dependency, the way `optional = true` and
`dep:name` do, and `[deps.shebang]` is already cargo-shaped so the slot is
there. What a feature gates is a unit of the manifest, which is a module row or
a dependency, rather than something inside a file.

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

**Dropping what nobody calls pays about 11%**, 233 ms against 261. Less than it
looked: an earlier run of this bench reported 3.7x, and that was a shaker
cutting `_deps_init`, which is called at file scope rather than from any
function, so nothing seeded it as a root. The artifact then loaded with a
dangling call, an empty tool table and no eager scan, which is why it was fast.
The answers still agreed, because `deps_has` resolves an unseen tool on demand,
so a broken artifact and a correct one were indistinguishable on that workload.

**Resolving the lazy dispatch is worth about 6 ms per dispatched function a
program actually touches.** `benches/lazy-dispatch` measures six at about 35 ms;
`benches/startup` calls one, where it is inside the noise. Built: the lowering
emits the winning implementation last, so the name is bound to the real function
by the time the file finishes loading.

Which one wins is not parsed. `text.sh` picks with a chain of `deps_has` and
`fs.sh` picks on a tool variant with a `uname` fallback under it, so the real
dispatch decides and the tool only watches: `nut_reload` is replaced by a
recorder, the stub names its choice and calls itself, and `nut_lazy_guard` stops
it there because the implementation was never loaded. The answer arrives and
none of the work behind it runs.

## What lowering has to do that is not obvious

Strip the per-file inclusion guards. `nut_once` answers about the file being
sourced, and concatenated every file is the same file: the first call registers
it and every guard after says "already loaded" and returns from the whole
thing. Found by the lowered arm defining one module and nothing else.

## `init` dissolves into `lib.nut`

Op's call, and it goes further than the draft that preceded it. That draft
answered his question, why does a lowered file need `init` at all now that the
manifest carries the shape, and concluded that it does not: the artifact drops
it, and `init` stays as the thing a person sources while developing.

He ruled that `init` should not stay. The manifest already carries the module
map, so the resolver becomes a smaller thing derived from it, and the bash
refusal moves out to whatever tool a person actually runs. What a consumer
sources changes, which is the largest blast radius of the three shapes that
were on the table and is the point: a file that exists only to look things up
in another file is a copy of that file with worse ergonomics.

The accounting below is what made the case, and it is why the answer went this
way rather than towards putting `init` itself on the floor.

`init` is 969 lines and twenty-four functions, and almost all of it is
resolution:

- Six functions answer "which file is this module" out of `lib.nut`:
  `_lib_nut_lookup`, `_lib_nut_modules`, `_nut_gate`, `_use_resolve`,
  `_use_mod_fragment`, `_use_super_resolve`.
- Four make a module load once: `nut_once`, `nut_reload`, `nut_lazy_guard`,
  `_nut_realpath`, with two associative tables behind them.
- Five are convenience: `nut_file`, `nut_dir`, `nutshell_loaded`,
  `nutshell_modules`, `nutshell_available`.
- Three lines are irreducible: find its own root, put `bin` on `PATH`, refuse
  bash 3.

A lowered file has had the first two done to it already. Resolution happened
when it was written; loading-once happened because everything is in one file.
What it actually referenced was `use` at file scope, `nut_reload` and
`nut_lazy_guard` inside stubs, and one `NUTSHELL_ROOT`. Four things, nine lines.

**And sourcing `init` is what kept the artifact off the floor.** `init` opens
with `declare -gA`, which is the first construct a POSIX shell refuses, so while
the preamble sourced it every module underneath could be perfectly POSIX and
none of it was reachable. The floor number counted files a POSIX shell could
read if it could get to them, and it could not get to any of them.

`init` stays bash 4 and stays loud about it. It is the development-time
resolver, reached from a machine that has bash, and the refusal at its top
exists because macOS ships 3.2 and a silent success there was worse than a
failure. Nothing about the floor asks that to change.

### Only with the dispatch decided

The preamble depends on pre-binding, and this is the constraint rather than a
detail. With the implementation bound ahead of the first call the stub never
runs, so `nut_reload` is never reached and stubbing `use` is correct. Without
it the stub does run, calls `nut_reload`, and a no-op there leaves it calling
itself until `nut_lazy_guard` stops it: the function answers nothing at all.

So `--no-prebind` keeps the old preamble and stays a bash artifact. That is not
a limitation to remove; it is the honest statement that a file which still has
to resolve something at run time still needs the resolver.

### What this does not give you

A lowering made on a machine with bash still takes the bash half of every
`#[shell(bash4)]` pair, because that gate asks the running shell. The artifact
is POSIX only where the closure has no such pair in it. Selecting the halves
rather than observing them is what the feature section above is for, and until
that exists the two sections together are the whole answer rather than either
alone.

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
`#[pub(super)]` is enforced. The audit grants it to every ancestor rather than
to the immediate parent alone, and reports a `super_at_root` finding where a
module has no parent to be visible from. **That is wider than the one line
above says** and is the agent's reading rather than a ratified call: the
argument is that `json::impl` names no file, so a rung that stopped at the
immediate parent would grant visibility to nothing. Worth a word before it is
relied on.

## Where enforcement is today

The gate catches a private cross-module call, including unmarked and
underscore-prefixed ones. Runtime catches nothing: `use attr` hands you
`_attr_name` and it runs, because sourcing fills one namespace.
