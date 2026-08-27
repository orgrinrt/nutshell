# What it costs to reach code that is not here

Whether a compiled helper is worth writing does not turn on C being faster
than shell at arithmetic. It turns on whether the saving survives the price of
reaching it. So this prices the reaching, and the price is a floor: no helper,
in any language, costs less than getting to it.

The workload is the sum of one to N, the same arithmetic on both sides, with N
as the knob. Somewhere on the sweep the shell's per-operation cost overtakes
the fork, and where that sits is the answer.

## The result

Forty calls per arm, on `Darwin arm64`, bash 5.3, compiled with `cc -O2`
before anything was timed. The figures are the best of seven repeats; the
spreads are in the committed CSVs beside this file and one of them is wide
(the N=10 forked arm runs 95 to 607).

| N | in-shell | forked helper | resident helper |
|---|---|---|---|
| 10 | 3 ms | 95 ms | 5 ms |
| 100 | 12 ms | 96 ms | 5 ms |
| 1000 | 98 ms | 101 ms | 5 ms |
| 10000 | 968 ms | 101 ms | 5 ms |

Two constants fall out of that, and they are the whole of it.

**A fork and exec costs about 2.4 ms, which is a thousand shell operations.**
The forked arm is flat from N=10 to N=10000, 95 ms against 101, because at
every size it is almost entirely the forking. A shell operation costs about
2.4 microseconds, so the crossover for a forked helper sits near N=1000 and is
visible in the table as the row where the two arms tie.

**A pipe round trip to a helper already running costs at most 0.125 ms, and
this bench cannot say how much less.** The resident arm reads 5 ms best and
6 ms worst at every size from N=10 to N=10000, which is the harness floor: it
does not move, so what is being measured is the resolution rather than the
work. Divided over forty calls that is 0.125 ms each, and the true figure is
somewhere below it, sharing the 5 ms with the one process start.

An earlier version of this paragraph asserted the 0.125 ms as a measurement and
then said in the next sentence that most of the 5 ms was the process start.
Both cannot be true, and the second is the more likely of the two.

So the comparison is a bound rather than a ratio. **A fork costs at least
nineteen times a pipe round trip**, and it is the fork, not the language on the
other side of it, that decides whether a helper pays. Nineteen is the floor of
that ratio; the real one is larger and needs a bench with more calls per arm to
pin, which is one number this file does not have.

## What that means for a helper written in C

**Forked, it needs about a thousand shell operations of work before it breaks
even.** That is a high bar and most things do not clear it. It is worth
checking a candidate against the number before writing any C, because the
intuition that C is faster is true and the intuition that it therefore wins is
not.

**Resident, it breaks even at about fifty operations and then wins without
limit.** At N=10000 it is 194 times the in-shell arm. Anything that runs many
times inside one long-lived process is a real candidate.

The catch is the shape of the program rather than the helper. A resident
helper needs somewhere to live, which means a process that lasts: a redraw
loop, an interactive session, a long batch. A script that starts, does one
thing and exits pays the 2.4 ms start and gets nothing back, so for a one-shot
tool the resident route collapses into the forked one.

## Portability, which the compile-on-install shape settles

The helper here is compiled from source, on the machine, before the run. That
is the shape the idea proposes and it disposes of the libc question by
construction: a binary built here inherits whatever is here, so there is no
ABI to match and nothing to detect.

What it does not dispose of is the compiler. A compiler is not everywhere:
minimal container images, appliance and embedded systems, and a mac without
the command line tools installed all lack one, and those are the machines a
POSIX floor exists for in the first place. So the compiled path is gated on
the compiler being present and the floor stays underneath it, which is the
same predicate every other tool gets rather than a new mechanism.

The C arms of this bench skip themselves where there is no compiler, and the
table says so instead of leaving a gap.

## What is not established here

**One machine, one libc, one shell.** `Darwin arm64` has expensive process
creation. Linux forks more cheaply, which would lower the thousand-operation
crossover, and nothing here says by how much. The resident number is a pipe
round trip and should travel better, but that is an expectation and not a
measurement.

**Nothing here says a resident helper is safe.** It prices one. A process that
outlives a call has a lifetime, an owner, and a way of dying halfway, and none
of that is measured or designed here.
