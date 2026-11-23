# What `toml_to_json` costs on a large file

The workspace's task tracker reads about 4 MB of TOML per run. The conversion
cost about 1.2 s per MB, 17.7 s for the tracker's files against 1.2 s for the
python the tracker would stop using, and that is what kept the port blocked.

The question is where that time goes and how far down it comes, on the tracker's
own shape: thousands of `[[action]]` tables whose values are string keys and
notes of several hundred bytes with escapes in them. The targets were stated
before the first run and are `bench_target`s in `bench.sh`, so a run that misses
one fails: 4 MB under 2 s on the floor alone, and under 0.5 s where taplo is
present.

Cold and warm are separate arms because they are separate questions. Cold is a
process that has never seen the file's text; warm is one that finds what an
earlier process kept for it. The tracker runs warm nearly always and cold once
per edit.

## Before, 2026-11-23, runs `results/20261123080408` (1 MB) and `results/20261123094815` (4 MB)

Linux x86_64, bash 5.2.21, 4 cores, 3 starts per arm, best start. The 1 MB run
was taken at a load average of 4 to 5 and the 4 MB run at 5 to 9, this container
sharing its host: both are upper bounds, and the gaps below are far wider than
the load accounts for.

| per start | 1 MB ms | 4 MB ms |
|---|---|---|
| floor, cold | 9004 | 251123 |
| floor, warm | 1255 | 10729 |
| taplo, cold | 11311 | 302829 |
| taplo, warm | 1330 | 11508 |
| mikefarah yq, cold | 17192 | not run |
| mikefarah yq, warm | 1361 | not run |

Every target missed, the floor by 125 times and taplo by 600.

Where it went, each step measured rather than divided out:

- Three bytes cut off the front of the text with `${v#...}`, the byte order
  mark, 230 s of the 4 MB tool path. `${v#pattern}` is quadratic in the value's
  length in bash 5.2 whatever the pattern is, `${v#abc}` as much as a pattern of
  bytes no locale reads, and this one sat in front of every backend read.
- The tool's JSON parsed into a tree by the json module's bash parser and
  written back out, which is why taplo was slower than the floor it is there to
  beat.
- The floor's writer appending to one growing string, which copies the whole of
  it each time: 1.2 s of the 1 MB floor path, and worse above it.
- The guard for an integer past 64 bits, whose pattern had groups in it; glibc
  matches those through a submatch search, 2 s in 80 KB of text with a digest in
  it.
- The floor spelling out the key of every `key = value` and every header against
  the chance of an error message, a tenth of the parse.

**holds for:** this host only, bash 5.2.21, taplo 0.10.0, mikefarah yq 4.44.3,
`toml` as of 667adfd, files of this shape: no float, no date-time, no integer
near the 64-bit end.

## After, 2026-11-23, runs `results/20261123102226` (1 MB) and `results/20261123102334` (4 MB)

Same host and bash, same arms, load average 3 to 4.

| per start | 1 MB before | 1 MB after | 4 MB before | 4 MB after |
|---|---|---|---|---|
| floor, cold | 9004 | 3043 | 251123 | 11384 |
| floor, warm | 1255 | 114 | 10729 | 332 |
| taplo, cold | 11311 | 346 | 302829 | 1476 |
| taplo, warm | 1330 | 110 | 11508 | 362 |
| mikefarah yq, cold | 17192 | 3198 | not run | not run |
| mikefarah yq, warm | 1361 | 108 | not run | not run |

Two of the four targets are met and two are missed:

- 4 MB on the floor, warm: 332 ms against 2000, met.
- 4 MB through taplo, warm: 362 ms against 500, met.
- 4 MB on the floor, cold: 11384 ms against 2000, missed. The parse is 11 s of
  it, 2.7 µs per byte of TOML read in bash, and the write 1.5 s. Meeting 2 s
  cold with no tool at all means another reader, not a faster version of this
  one.
- 4 MB through taplo, cold: 1476 ms against 500, missed. taplo itself is 660 ms
  of it, the compaction 230 ms, the write of the kept JSON 190 ms and the start
  of the process 250 ms. Under 500 ms would need taplo to print compact JSON,
  which it has no flag for.

mikefarah yq stays out of the large-file path and off the 4 MB arms: it reads
1 MB in 3.2 s where taplo takes 0.35 s, and a 4 MB start would run for minutes.

What the time buys, warm: the JSON kept for the file's text, read back and
printed, so a 4 MB text is parsed once per edit of it rather than once per
process.

**holds for:** this host only, bash 5.2.21, taplo 0.10.0, mikefarah yq 4.44.3,
`toml` as of this commit, files of this shape. A file holding a float, a
date-time, an integer past 64 bits, a `null` or a key with a separator in it is
the floor's whatever its size, so the taplo arms do not describe it.
