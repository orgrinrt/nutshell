# What deciding an implementation at first call costs

`text_grep` and its twelve siblings are stubs. On the first call each asks
`deps_has` which tools are present, picks an implementation, `nut_reload`s the
module holding it, and is replaced by it. Every call after that is the real
function and costs nothing.

So the cost is once per process and once per dispatched function, and a
lowering knows the answer already. This prices what it would save.

## The result

**About 35ms per process, at six dispatched functions, which is 86% of the
lazy arm.** It scales with how many are used and it is invisible below three.

| functions used | pre-bound against deciding |
|---|---|
| 1 | within the noise |
| 3 | within the noise |
| 6 | 86%, and again 88% on a second run |

Ten fresh shells per iteration, so a per-process saving of 35ms shows up as
about 350ms across the ten. Each iteration is a fresh shell because the cost is
paid once and a loop inside one shell would measure it once and then measure
nothing.

## Where the cost is, which is not where it looks

**Not in `deps_has`.** The middle arm hands the resolved tool table down through
the environment so each shell skips every tool lookup, and it measures inside
the noise of the lazy arm on every run. The deciding is not what costs.

**In the module load.** What is left between the middle arm and the pre-bound
one is the `nut_reload`: finding the implementation module, reading it, and
sourcing it. That is a file per dispatched function.

That decomposition is the useful part, because it says what a lowering has to
do to collect the win. Baking in the *answer* to `deps_has` buys nothing
measurable. Baking in the *implementation*, so no module is loaded at first
call, is the whole of it.

## How this sits against the startup bench

`benches/startup` found that resolving `use` ahead of time does not pay and
that dropping what nothing calls pays 3.7x. This is the same shape one level
down: the bookkeeping half of a lowering is noise, and the half that avoids
reading a file is the win.

A shaker and a pre-binder want the same thing, which is worth saying because it
suggests one pass rather than two: if the lowering already knows which
implementation is chosen, the modules for the other two are exactly what the
shaker should be dropping.

## What is not established here

**The scaling is measured at one, three and six**, and thirteen functions
dispatch this way. Nothing here says the sixth and the thirteenth cost the
same, and a library where they share an implementation module would flatten
after the first.

**One host, one machine, bash 5.3.** The saving is a file read per function, so
a slower disk moves it up and a warm page cache moves it down. The floor is
where this matters most and is exactly where it was not measured.

**This is not a lowering.** The pre-bound arm loads the implementation modules
by name before the first call, which is a stand-in for emitting them into one
file. A real lowering would also drop the stub, and that is unmeasured.

**Six of the thirteen** are exercised, the ones whose call shapes were easy to
write down. The others may decide differently.
