# What lowering saves at load time

Three arms, all running the same workload and compared on its answer rather
than on the loaded surface, because a shaken arm loads less by design.

| arm | best ms | against the first |
|---|---|---|
| resolved through the manifest | 247 | |
| lowered, `use` resolved already | 235 | within the noise |
| lowered and shaken | 67 | **26%** |

Reproducible across runs. Six modules, a ten file closure.

## The answer

**Resolving `use` ahead of time does not pay.** Twelve milliseconds in two
hundred and fifty, and the harness reports it as noise. The cost is parsing the
files, not finding them.

**Dropping what nothing calls does.** 3.7x, and it is the whole of the win.
Statically, for one real program, 24 of the 165 functions it loads are
reachable and 141 are not.

So the lowering worth building is a shaker. The resolution half is a
simplification rather than an optimisation and should be argued for on those
grounds if at all.

## Four things a lowering has to do, each found by getting it wrong

**Strip the per-file inclusion guards.** `nut_once` answers about the file
being sourced, and concatenated every file is the same file: the first call
registers it and every guard after says "already loaded" and returns from the
whole thing. The lowered arm defined one module and nothing else.

**Register what it contains rather than stubbing the resolver.**
`use() { return 0; }` looks equivalent and is not, because `nut_reload` goes
through `use`. `fs_size` answered nothing.

**Rewrite `super::` away.** It resolves relative to the file that wrote the
call, through `BASH_SOURCE[1]`, and concatenated every call comes from the
lowered file. In a temp directory with no manifest above it, that resolves to
nothing. A lowering knows the unit at lower time, which is the point.

**Shake by cutting definitions out of the file, not by rebuilding from
`declare -f`.** Rebuilt, the result is functions and nothing else: every
module's file-scope initialisation goes. `deps.sh` populating its tool table at
load time was the one that showed, and `fs_size` then read an empty variant
table and chose no implementation.

## What the shaker here is, and is not

It reads names rather than parsing shell, so a name in a comment or a string
counts as a use. That over-retains, which is the safe direction, and makes 26%
a **floor** on what a real pass could reach rather than a claim about what it
would.

What it cannot see is a name assembled at run time. Every `nut_reload` in this
library is written literally for exactly that reason; two in `fs.sh` were not
until today, and a shake would have kept one of the three stat implementations
and dropped two, failing at first call on whichever machine has the other
`stat`.

The closure follows `nut_reload` targets as well as `use`. Following only `use`
left the impl modules out and the harness refused the run.

## What is not measured

Whether the shake is safe for a program whose call graph is not visible: a
caller reaching a library function through a variable, or a task file loaded by
name at run time. hulilupteri does the second, so the number here does not
transfer to it without checking that first.
