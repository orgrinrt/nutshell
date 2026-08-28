# What a lowered form saves at load time

Three arms, all running the same workload and compared on its answer rather
than on the loaded surface, because a shaken arm loads less by design.

The lowering is `bin/nut-lower`, not a copy of it. This bench had its own until
the tool existed, which is how the tool was found: every gotcha in it was
discovered here, by getting it wrong and watching the harness refuse the run
for arms that disagreed. Measuring a copy meant the numbers were not about the
thing that ships.

## Superseded, 2026-08-28: `_deps_init` no longer scans at load

Everything below was measured while `deps.sh` resolved all eighteen tools when
the module was sourced. It does not any more, and the numbers move so far that
the conclusion inverts.

| arm | then | now |
|---|---|---|
| resolved through the manifest | 248 | 249 |
| lowered, dispatch left to run | 221 | 249 |
| lowered, `use` resolved already | 216 | **60** |
| lowered and shaken | 217 | **61** |

The eager scan was 209ms that every arm paid equally, so it hid the difference
between them. With it gone, **the lowering is a 4x** and what it removes is the
resolution, which this file called noise because it was measuring underneath a
much larger constant.

Shaking is still noise: 61 against 60, the spreads touching, exactly as before.
That part of the old answer stands and is the one the tree-shaking question
asked.

Per module, now that nothing dominates: `os` 27ms, `string` 26, `validate` 46,
`deps` 67, `toml` 91, `fs` 99, `text` 102. Before, every one of those was two
hundred and something and the number was `deps`.

**holds for:** bash 5.3, `Darwin arm64`, this workload's 6 modules, `deps`
resolving on demand. The section below is kept because it is the reasoning that
found the scan, and because a superseded measurement with its successor beside
it is worth more than a deleted one.

## The answer, and it is not the one this file used to give

**Almost none of the load cost is what a shaker can remove.** `use deps` alone
takes 209ms of a 225ms library load, and it is one thing: `_deps_init` scanning
for eighteen tools with `command -v` when the module is sourced. Everything
else together is about 16ms.

So resolving `use` ahead of time is noise, which this file already said, and
**dropping unreferenced function definitions is nearly noise as well**, which it
did not.

| arm | best ms | against the first |
|---|---|---|
| resolved through the manifest | 248 | |
| lowered, dispatch left to run | 221 | 89% |
| lowered, `use` resolved already | 216 | 87% |
| lowered and shaken | 217 | 87%, and the spreads nearly touch |

## Deciding the dispatch here is worth about 5ms on this workload, and that is per function

The middle pair is the price of resolving the lazy dispatch at lower time
rather than at first call: same concatenation, same closure, and the only
difference is whether `fs_size` is the implementation when the file finishes
loading or is still a stub that will go and fetch one.

**5ms, and the spreads overlap, so on this workload it is inside the noise.**

That is not a small win hiding; it is one dispatched function. This workload
calls exactly one, and `benches/lazy-dispatch` measures six at about 35ms, so
the two agree at roughly **6ms per dispatched function a program actually
touches**. A program calling one saves nothing worth measuring and a program
calling all thirteen saves most of a tenth of a second.

**holds for:** bash 5.3, `Darwin arm64`, this workload's 6 modules and its one
dispatched call, tools as this machine has them. Nothing here says what it
costs where the winning implementation is a different one.

The mechanism is asserted rather than timed in `tests/nut_lower_test.sh`:
`nut_reload` is made a canary, and a dispatched function has to answer without
it firing. That fails on the dispatch being present rather than on it being
slow, and it carries the control that proves the canary is wired to something.

## What the earlier 26% actually was

This file used to report the shaken arm at 67ms against 247, a 3.7x win, and
called it the value of dropping what nothing calls.

It was the shaker dropping `_deps_init`. Nothing in the entry script names it,
because it is called at file scope rather than from any function, so nothing
seeded it as a root and the definition was cut while the call stayed. The
lowered file then loaded with a dangling call, an empty tool table, and no
eager scan, which is why it was fast.

**The answers still agreed**, which is why neither the harness nor the tests
caught it: `deps_has` resolves a tool it has not seen on demand, so an empty
eager table produces the same results by a slower path per lookup. A broken
artifact and a correct one are indistinguishable on this workload.

Seeding roots from file-scope calls fixes the shaker, the tool table is
populated again, and the win goes away with it.

## Where the win actually is

**In `deps.sh`, and it belongs to every program rather than to lowered ones.**
The eager scan resolves eighteen tools at load whether or not the program asks
about any of them, and `deps_has` already resolves on demand for anything not
in that list. The scan exists to populate the capability table, which nothing
needs until `deps_can` is called.

Making it lazy is a change to one module, worth about 190ms of a 225ms load,
and it needs no lowering at all. That is the next thing, and it is filed rather
than done here because it is a design change to a module and this is a bench.

A lowering could then bake in the answers it knows, which is what
`benches/lazy-dispatch` prices at about 35ms per process. That is a real
remaining win and it is an order of magnitude smaller than the one above.

## Four things a lowering has to do, each found by getting it wrong

These stand. Each produced a lowered file that loaded cleanly and answered
nothing, and each is a test in `tests/nut_lower_test.sh`.

**Strip the per-file inclusion guards.** `nut_once` answers about the file being
sourced, and concatenated every file is the same file: the first call registers
the lowered one and every guard after says already-loaded and returns from the
whole thing. The lowered arm defined one module and nothing else.

**Register what it contains, keyed by canonical path.** `use` resolves the
module, runs the path through `_nut_realpath`, and checks that. Keyed by module
name instead, nothing matches and every `use` sources its file again: the
answers stay correct and the work is done twice. The tests saw nothing and this
bench saw it at once, as the shaken arm at 261ms against an expected 55.

**Rewrite `super::` away.** It resolves relative to the file that wrote the
call, through `BASH_SOURCE[1]`, and concatenated every call comes from the
lowered file.

**Shake by cutting definitions out of the file, not by rebuilding from
`declare -f`.** Rebuilt, the result is functions and nothing else and every
module's file-scope initialisation goes.

And a fifth, which is the one this round added: **seed the roots from file-scope
calls as well as from the entry script**, or a module that does work when it
loads has that work cut out from under it.

## What is not established here

One host, one machine, bash 5.3, six modules and a ten file closure. The
185ms is eighteen `command -v` calls, so a machine with a slower `PATH` lookup
or a colder cache moves it, and the floor is where that matters most and is
where it was not measured.
