# What a nutshell script pays before its first line

The question is whether a hook that fires on every tool call can be a nutshell
script, which needs a script with no `use` to start under 50ms and one with
`use json` under 80ms. Both targets were stated before the first run and are
`bench_target`s in `bench.sh`, so a run that misses one fails.

## Before, 2026-11-23, run `results/20261123003530`

Linux x86_64, bash 5.2.21, 4 cores, 7 batches of 10 starts per arm, best batch.

| per start | ms |
|---|---|
| bash, nothing loaded | 3.9 |
| bash sourcing init | 5.5 |
| init, use deps | 61.8 |
| init, use extern log | 238.8 |
| script, no use, no manifest | 249.5 |
| script, no use, 300-line manifest | 345.2 |
| script, use json, no manifest | 353.7 |
| script, use toml, 300-line manifest | 341.1 |

Where it goes: the interpreter 3.9ms, `init` 1.6, `deps` 56.3, and the two
modules `bin/nutshell` loads for itself, `extern` and `log`, 233ms. The pin read
of a 300-line manifest adds 96ms, and `use json` 104ms on top of the bare
script. All three targets missed, by 200ms, 295ms and 274ms.

**holds for:** this host only, bash 5.2.21, `bin/nutshell` as of 2173589, tools
as this container has them.
