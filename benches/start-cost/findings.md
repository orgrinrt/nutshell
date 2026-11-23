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

## After, 2026-11-23, run `results/20261123010643`

Same host and bash, same arms, all three targets met.

| per start | before ms | after ms |
|---|---|---|
| bash, nothing loaded | 3.9 | 3.1 |
| bash sourcing init | 5.5 | 5.2 |
| init, use deps | 61.8 | 18.1 |
| init, use extern log | 238.8 | 54.8 |
| script, no use, no manifest | 249.5 | 6.4 |
| script, no use, 300-line manifest | 345.2 | 25.7 |
| script, use json, no manifest | 353.7 | 59.0 |
| script, use toml, 300-line manifest | 341.1 | 27.2 |

What moved it, in the order of its share:

- The interpreter loads nothing for itself. `extern` and `log` load only for a
  manifest that pins an engine, and `toml` only when there is a manifest.
- No fork on the way to a module. Each `use` captured the resolver, the
  `lib.nut` lookup and the realpath, and `nut_once` the realpath again; `deps`
  captured `_deps_find_tool`, which ran `which`, so each tool asked about was a
  fork and an exec, and the first one loaded `deps::pins` and read the manifest
  inside the capture and threw it away. A json start went from 31 forks to 0.
- `lib.nut` indexed once per process and searched by a regex: `${s#*pat}`
  matches against every prefix, 870us a lookup against 45us.
- `nut_key` hexes from a table under bash, about a third of the time, with the
  same output dash gives.
- The toml floor's tree kept between processes, checked against the file's
  text: the pin read of the 300-line manifest went from 96ms to 19ms.

What is left, and why:

- `use json` is 52.6ms over a bare script: `deps` 13ms, the first tool question
  reading nutshell's own manifest for `[deps.paths]` through `toml` (its load
  and the kept tree), and the four backends json loads for the tools present.
  Picking the backend at the first call instead was tried and dropped: a call
  inside `$(...)` would pick in the subshell and lose it, so every captured call
  would pay the pick again.
- The pin read is the `toml` load plus reading the kept tree back, about 14ms
  and 5ms. The first process after the manifest changes parses it, about 37ms
  for 332 lines; these numbers are a warm cache.

**holds for:** this host only, bash 5.2.21, `XDG_CACHE_HOME` writable and warm,
tools as this container has them.

## After review, 2026-11-23, run `results/20261123013407`

Same host and bash. Three changes since the run above: the public functions
the old preload put in reach are stubs again, loaded on their first call; a
kept tree is taken only where its file and directory are the reader's and
nobody else can write them, which `find -perm` answers in one fork; and an arm
with a cache directory of its own per start, so nothing is kept.

| per start | ms |
|---|---|
| bash, nothing loaded | 3.3 |
| bash sourcing init | 5.1 |
| init, use deps | 17.4 |
| init, use extern log | 55.6 |
| script, no use, no manifest | 8.2 |
| script, no use, 300-line manifest | 31.3 |
| script, use json, no manifest | 65.6 |
| script, use toml, 300-line manifest | 29.7 |
| script, no use, 300-line manifest, cold | 126.7 |

All three targets met. The bare script went from 6.4ms in run
`20261123010643`, before the stubs, to 8.5 in `20261123012558` and 8.2 here,
with them: about 2ms a start, which no committed run splits between the 165
stubs and the other changes. The ownership check is about 5ms of the warm pin
read. The cold pin read is 118ms over the bare script against 23ms
warm: the parse, the toml load, and writing the tree in a subshell for its
umask. It is paid once per manifest text and per user.

**holds for:** this host only, bash 5.2.21, `XDG_CACHE_HOME` writable, warm in
every arm but the cold one, tools as this container has them.

## Review pass 2, 2026-11-23, runs `results/20261123020608` and `results/20261123021437`

Same host and bash. A new arm, twenty `x="$(fs_basename /a/b)"` with no `use`:
each `$(...)` is a subshell, so a stub called there loads `fs` in it and the
load is lost with it. Run `20261123020608` is the tree at f202667, before the
interpreter loaded such a module ahead and with `_nut_prelude_keep` capturing a
module's row on every first load; `20261123021437` is the tree after both
fixes: the module loaded ahead, and the keep asked only where the script's text
defines a function of the table.

| per start | f202667 ms | after ms |
|---|---|---|
| bash, nothing loaded | 3.1 | 3.0 |
| bash sourcing init | 4.9 | 5.2 |
| init, use deps | 19.7 | 17.9 |
| init, use extern log | 60.9 | 56.8 |
| script, no use, no manifest | 8.0 | 8.7 |
| script, no use, 300-line manifest | 46.6 | 33.4 |
| script, use json, no manifest | 95.2 | 62.2 |
| script, use toml, 300-line manifest | 48.5 | 29.3 |
| script, no use, 300-line manifest, cold | 137.1 | 121.0 |
| script, 20 captures of a stub, no manifest | 1508.0 | 79.2 |

The f202667 run missed the json target, 95.2 against 80: a fork on the first
load of each module the prelude table names, to tell a script's own function
from a stub, about 3ms a module, and a pin read or a `use json` loads several.
The text of the script is now read once before it runs, about 0.2ms for a short
script, and the fork is taken only where the script defines one of the table's
functions. All three targets met after. The twenty captures went from 1508ms
to 79ms.

**holds for:** this host only, bash 5.2.21, `XDG_CACHE_HOME` writable, warm in
every arm but the cold one, tools as this container has them.

## The hook path, 2026-11-23, runs `results/20261123052230` and `results/20261123055727`

Same host and bash, load about 1.3 on 4 cores for both. Three arms for what a
per-tool-call hook does: `use json` and one `json_get` of a plain path from a
2 KB payload on stdin, the first `deps_has jq`, and a start with HOME unset.
Targets stated before the work: 25ms for the json arm, 14ms for the first
`deps_has` (a bare start, about 9ms, and 5ms).

| per start | 3a8cb8b ms | after ms |
|---|---|---|
| bash sourcing init | 5.1 | 4.6 |
| init, use deps | 17.7 | 8.4 |
| init, use extern log | 55.4 | 39.0 |
| script, no use, no manifest | 8.8 | 7.9 |
| script, no use, 300-line manifest | 34.1 | 23.8 |
| script, use json, no manifest | 67.4 | 13.2 |
| script, use json, one json_get of 2 KB stdin | 74.4 | 16.9 |
| script, no use, first deps_has jq | 45.6 | 12.7 |
| script, no use, HOME unset | fails | 7.8 |

Where it went:

- `use json` loaded `deps`, asked it about four tools and loaded every backend,
  the builders and `json_query`. It loads the reader in bash and the path
  splitter now; the rest loads at the first call that needs it.
- The first tool question loaded `toml` and checked its kept tree of the
  manifest for a pin, about 20ms. A manifest whose text never spells the tool
  cannot pin it, which one read of the file tells.
- `use` keyed each file it loaded through `nut_key`, which hexes a path a byte
  at a time, three times a module: most of what a `use` cost. The tables are
  one associative array now. `use deps` went from 12.6ms over `init` to 3.8.
- `json_get` ran jq twice, about 9ms. The reader in bash answers a plain path
  where its text is jq's to the byte. Its escape decoding cut the rest of the
  string once per escape, 5ms for the payload's command; it substitutes over
  the whole string now.

The floor against jq, `json_get` of one top-level key, best of three, in one
process (an ad-hoc measurement, not a bench arm): jq is about 9ms whatever the
size up to 50 KB. The floor costs about 90us a value: 2.5ms at 8 values, 9.8ms
at 53, 34ms at 203. A document of one long string costs it 2.6ms at 2 KB,
9.5ms at 32 KB, 40ms at 128 KB. So the floor takes a document up to 32 KB and
parses at most 64 values, past which it hands the question to jq having spent
less than one run of jq.

Both targets met: 16.9 against 25, and 12.7 against 14 (4.8ms over the bare
start). What is left in the json arm is the reader's parse of the payload,
about 3ms, and the four `use`s at about 0.8ms each; in the deps arm, building
the `lib.nut` index on the first `use` of a process, about 1ms.

A `$(json_get ...)` parses the document in the subshell and loses the tree with
it, as a `$(json_query ...)` loads `json::query` and `deps` in it.

**holds for:** this host only, bash 5.2.21, jq 1.7, `XDG_CACHE_HOME` writable,
warm in every arm but the cold one, tools as this container has them.
